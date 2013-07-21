require 'redmine'
require 'ref_issues/parser'

module WikiListsRefIssue
  Redmine::WikiFormatting::Macros.register do
    desc "Displays a list of referer issues."
    macro :ref_issues do |obj, args|
      
      parser = nil
      
      begin
        parser = WikiLists::RefIssues::Parser.new obj, args, @project
      rescue => err_msg
        msg = "<br>parameter error: #{err_msg}<br>"+
          "[optins]<br>"+
          "-s[=WORD[|WORD...]] : search WORDs in subject<br>"+
          "-d[=WORD[|WORD...]] : search WORDs in description<br>"+
          "-w[=WORD[|WORD...]] : search WORDs in subject and/or description<br>"+
          "-i=CustomQueryID : specify custom query by id<br>"+
          "-q=CustomQueryName : specify custom query by name<br>"+
          "-p[=identifier] : restrict project<br>"+
          "-f:FILTER[=WORD[|WORD...]] : additional filter<br>"+
          "-l[=attribute] : display linked text<br>" +
          "[columns] : {"
        attributes = Issue.attribute_names
        while attributes
          msg += attributes[0...5].join(',') + ', '
          attributes = attributes[5..-1]
          msg += "<br>" if attributes
        end
        msg += "cf_* }"
        msg += '<br>'
        raise msg.html_safe
      end

      unless parser.has_serch_conditions? # 検索条件がなにもなかったら
        # 検索するキーワードを取得する
        parser.searchWordsW << parser.defaultWords(obj)
      end
      
      @query = parser.query @project

      extend SortHelper
      extend QueriesHelper
      extend IssuesHelper
      sort_clear
      sort_init(@query.sort_criteria.empty? ? [['id', 'desc']] : @query.sort_criteria);
      sort_update(@query.sortable_columns);
      @issue_count_by_group = @query.issue_count_by_group;

      parser.searchWordsS.each do |words|
        @query.add_filter("subject","~", words)
      end

      parser.searchWordsD.each do |words|
        @query.add_filter("description","~", words)
      end

      parser.searchWordsW.each do |words|
        @query.add_filter("subjectdescription","~", words)
      end

      parser.additionalFilter.each do |filterString|
        if filterString=~/^([^\=]+)\=([^\=]+)$/
          filter = $1
          values = $2.split('|')
          res = @query.add_filter(filter, '=', values)
        else
          res = @query.add_filter(filterString, '=', parser.defaultWords(obj))
        end
        raise 'failed add_filter: '+filterString if res.nil?
      end

      @query.column_names = parser.columns unless parser.columns.empty?

      @issues = @query.issues(:order => sort_clause, 
                              :include => [:assigned_to, :tracker, :priority, :category, :fixed_version]);

      if parser.onlyLink
        disp = String.new
        atr = parser.onlyLink
        @issues.each do |issue|
          if issue.attributes.has_key?(atr)
            word = issue.attributes[atr]
          else
            issue.custom_field_values.each do |cf|
              if 'cf_'+cf.custom_field.id.to_s == atr || cf.custom_field.name == atr
                word = cf.value
              end
            end
          end

          disp << ', ' if disp.size!=0
          disp << link_to("#{word}", {:controller => "issues", :action => "show", :id => issue.id})
        end
      else
        disp = context_menu(issues_context_menu_path)
        disp << render(:partial => 'issues/list', :locals => {:issues => @issues, :query => @query});
      end

      return disp.html_safe
    end
  end
end
