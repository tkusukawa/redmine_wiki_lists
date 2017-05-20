module RedmineWikiLists::WikiList
  Redmine::WikiFormatting::Macros.register do
    desc 'Displays a list of wiki pages with text elements (only inside wiki-pages).'
    macro :wiki_list do |obj, args|
      # 引数をパース
      cond = ''
      joins = ''
      table_width = ''
      column_keys = []
      column_names = []

      begin
        raise '- no parameters' if args.count.zero?

        args.each do |arg|
          arg.strip!

          if arg =~ /\A\-([^\=]*)(\=.*)?\z/ # オプション表記発見
            case $1
              when 'c' # リストアップの対象を子ページに限定する場合
                cond << ' AND ' if cond != ''
                cond << "parent_id = #{obj.page.id}"
              when 'p' # リストアップの対象を特定の別プロジェクトのWikiに限定する場合
                if arg=~/\A[^\=]+\=(.*)\z/ then # プロジェクト名を指定
                  name = $1.strip
                  prj = Project.find_by_name(name)
                  cond << ' AND ' if cond != ''
                  cond << "project_id = #{prj.id}"
                else # プロジェクト名の指定が無い場合は当該WIKIのPJに限定
                  cond << ' AND ' if cond != ''
                  cond << "project_id = #{obj.project.id}"
                end

                joins << 'INNER JOIN wikis ON wiki_pages.wiki_id = wikis.id'
              when 'w' # 表の横幅
                if arg =~ /\A[^\=]+\=(.*)\z/ # 幅を取得
                  width = $1.strip
                  table_width = 'width="' + width + '"'
                end
              else
                raise "- unknown option: #{arg}"
            end
          else # オプションでない場合はカラム指定
            if arg =~ /\A(.*)\|(.*)\|(.*)\z/ # 抽出キーワードと別にカラム表示名と列幅の指定がある場合
              column_keys.push($1.strip)
              column_names.push($2.strip + '|' + $3.strip)
            elsif arg =~ /\A(.*)\|(.*)\z/ # 抽出キーワードと別にカラム表示名の指定がある場合
              column_keys.push($1.strip)
              column_names.push($2.strip)
            else # カラム表示名の指定が無い場合は抽出キーワードをカラム表示名にする
              column_keys.push(arg.strip)
              column_names.push(arg.strip)
            end
          end
        end
      rescue => err_msg
        msg = <<-TEXT
- parameter error: #{err_msg}<br>
usage: {{wiki_list([option]*,[column]*)}}<br>
[option]<br>
-c : search child pages<br>
-p=[PROJECT NAME] : restrict search pages by project<br>
-w=[WIDTH] : table width<br>
[column]<br>
+title[| COLUMN_NAME] -> show page title<br>
+alias[| COLUMN_NAME] -> show page aliases<br>
KEYWORD[| COLUMN_NAME] -> scan KEYWORD and show following words to EOL<br>
KEYWORD\\TERMINATOR[| COLUMN_NAME] -> scan KEYWORD and show following words to TERMINATOR
TEXT
        raise msg.html_safe
      end

      if column_keys.count.zero?
        column_names.push 'title'
        column_keys.push '+title'
      end

      disp = "<table #{table_width}><tr>"

      # カラム名(最初の行)を作成
      column_names.each do |column_name|
        if column_name =~ /\A(.*)\|(.*)\z/ then
          disp << '<th width="'+$2+'">' + $1 + '</th>'
        else
          disp << "<th>#{column_name}</th>"
        end
      end

      disp << '</tr>'
      # Wikiページの抽出
      wiki_pages = WikiPage.joins(joins).where(cond)

      wiki_pages.each do |wiki_page| #---------------- Wikiページ毎の処理
        next unless wiki_page.visible?
        # 1ページに抽出キーワードが複数あった場合に複数行表示するため一旦表示行を配列に記憶する
        lines_by_page = [[]] # 最初は1ページ1行からスタート
        column_num = 0

        column_keys.each do |column_key| #---------------- カラム毎の処理
          case column_key
            when '+title' # Wikiページ名
              html =
                  link_to(wiki_page.title,
                          controller: 'wiki', action: 'show',
                          project_id: wiki_page.project, id: wiki_page.title)
              RedmineWikiLists::WikiList.set_lines(lines_by_page, column_num, html)
            when '+alias' # Wikiページの別名
              redirects = WikiRedirect.where(wiki_id: wiki_page.wiki_id, redirects_to: wiki_page.title)
              html = ''

              redirects.each do |redirect|
                html << '<br>' if html.present?
                html << redirect.title
              end

              RedmineWikiLists::WikiList.set_lines(lines_by_page, column_num, html)
            when '+project' # Wikiページのプロジェクト名
              RedmineWikiLists::WikiList.set_lines(lines_by_page, column_num, wiki_page.project.to_s)
            else # それ以外はWikiページの中からキーワードで表示要素を抽出する
              new_lines = [] # カラムキーワードが抽出される毎にこの変数に表示行を追加する

              if column_key =~ /\A(.*)\\(.*)\z/
                keyword = Regexp.escape($1.strip)
                terminator = Regexp.escape($2.strip)
                matches = wiki_page.text.scan /#{keyword}[\s\S]*?#{terminator}/ # キーワードから終端文字列までを抽出
              else
                keyword = Regexp.escape(column_key)
                terminator = false
                matches = wiki_page.text.scan /#{keyword}.*\z/ # キーワードから行末までを抽出
              end

              matches.each do |match| # 抽出されたキーワード毎の処理
                # キーワードの後ろの文字列を抽出
                match =~
                    if terminator
                      /\A#{keyword}([\s\S]*)#{terminator}/
                    else
                      /\A#{keyword}(.*)\z/
                    end

                if $1
                  html = textilizable($1.strip) # 前後の空白を覗いてWiki表記解釈
                  # Wikiページ内のこれまでのカラム処理で生成されたlinesに表示内容を記入
                  RedmineWikiLists::WikiList.set_lines(lines_by_page, column_num, html)

                  lines_by_page.each do |line|
                    new_lines.push(line.dup) # 本カラムによって生成される行にコピーを追加
                  end
                end
              end

              if new_lines.length.zero? # キーワードが１つも抽出されていなかったら空文字を入れておく
                RedmineWikiLists::WikiList.set_lines(lines_by_page, column_num, '')
              else # 抽出があった場合は本カラムで作られた新しい表示行をページ表示行にする
                lines_by_page=new_lines
              end
          end # case columnKey

          column_num += 1
        end # カラム毎の処理

        # 配列に記憶されたページ内の表示内容をHTMLに吐き出す
        lines_by_page.each do |line|
          disp << '<tr>'

          line.each do |column|
            disp << "<td>#{column}</td>"
          end

          disp << '</tr>'
        end
      end # Wikiページ毎の処理

      disp << '</table>'
      disp.html_safe
    end
  end

  # 配列の全ての要素配列のcolumn_num番目にstrを書きこむ
  def set_lines(lines, column_num, str)
    lines.each do |line|
      line[column_num] = str
    end
  end

  module_function :set_lines
end
