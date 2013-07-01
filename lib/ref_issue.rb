require 'redmine'
require 'ref_issues/parser'

module WikiListsRefIssue
  Redmine::WikiFormatting::Macros.register do
    desc "Displays a list of referer issues."
    macro :ref_issues do |obj, args|
      
      parser = nil
      
      begin
        parser = WikiLists::RefIssues::Parser.new args, @project
      rescue => err_msg
        msg = "parameter error: #{err_msg}<br>"+
          "[optins]<br>"+
          "-s=WORD[|WORD[|...]] : search WORDs in subject<br>"+
          "-d=WORD[|WORD[|...]] : search WORDs in description<br>"+
          "-w=WORD[|WORD[|...]] : search WORDs in subject and/or description<br>"+
          "-i=CustomQueryID : specify custom query<br>"+
          "-q=CustomQueryName : specify custom query<br>"+
          "-p[=identifier] : restrict project<br>"+
          "-f:FILTER[=WORD[|WORD]] : additional filter<br>"
          "[columns]<br>"+
          "project,tracker,parent,status,priority,subject,author,assigned,updated,<br>"+
          "category,fixed_version,start_date,due_date,estimated_hours,done_ratio,created,cf_*"
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
          @query.add_filter(filter, '=', values)
        else
          @query.add_filter(filterString, '=', parser.defaultWords(obj))
        end
      end

      @query.column_names = parser.columns unless parser.columns.empty?

      @issues = @query.issues(:order => sort_clause, 
                              :include => [:assigned_to, :tracker, :priority, :category, :fixed_version]);
      
      disp = context_menu(issues_context_menu_path);
      disp << render(:partial => 'issues/list', :locals => {:issues => @issues, :query => @query});

      return disp;
    end
  end
end
