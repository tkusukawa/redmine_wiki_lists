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
          "-t[=attribute] : display text<br>" +
          "-l[=attribute] : display linked text<br>" +
          "-c : count issues<br>" +
          "[columns] : {"
        attributes = IssueQuery.available_columns
        while attributes
          attributes[0...5].each do |a|
            msg += a.name.to_s + ', '
          end
          attributes = attributes[5..-1]
          msg += "<br>" if attributes
        end
        msg += 'cf_* }<br/>'
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

      models = {"tracker"=>Tracker,"category"=>IssueCategory,"status"=>IssueStatus,"assigned_to"=>User,"version"=>Version, "project"=>Project}
      ids = {"tracker"=>"tracker_id","category"=>"category_id","status"=>"status_id","assigned_to"=>"assigned_to_id","version"=>"fixed_version_id","project"=>"project_id"}
      attributes = {"tracker"=>"name","category"=>"name","status"=>"name","assigned_to"=>"login","version"=>"name","project"=>"name"}

      parser.additionalFilter.each do |filterString|
        filter = ''
        operator = ''
        values = nil
        if filterString=~/^([^ ]*) +([^ ]*)$/
          filter = $1
          operator = $2
        elsif filterString=~/^([^ ]*) +([^ ]*) +(.*)$/
          filter = $1
          operator = $2
          values = $3.split('|')
        elsif filterString=~/^(.*)=(.*)$/
          filter = $1
          operator = "="
          values = $2.split('|')
        else
          filter = filterString
          operator = "="
          values = parser.defaultWords(obj)
        end

        values.collect! do |v|
          v.strip!
          if v =~ /^\[(.*)\]$/
            atr = $1
            if obj.attributes.has_key?(atr)
              v = obj.attributes[atr]
            else
              obj.custom_field_values.each do |cf|
                if 'cf_'+cf.custom_field.id.to_s == atr || cf.custom_field.name == atr
                  v = cf.value
                end
              end
            end
          end
          v.to_s
        end

        if models.has_key?(filter)
          tgtObj = models[filter].find_by attributes[filter]=>values.first
          raise "can not resolve '#{values.first}' in #{models[filter].to_s}.#{attributes[filter]} " if tgtObj.nil?
          filter = ids[filter]
          values = [tgtObj.id.to_s]
        end

        res = @query.add_filter(filter , operator, values)
        if res.nil?
          msg =  "<br/>failed add_filter: #{filterString}<br/>" +
                 '[FILTER] : {'
          cr_count = 0
          @query.available_filters.each do |k,f|
            if cr_count >= 5
              msg += '<br/>'
              cr_count = 0
            end
            msg += k.to_s + ', '
            cr_count += 1
          end
          models.each do |k, m|
            if cr_count >= 5
              msg += '<br/>'
              cr_count = 0
            end
            msg += k.to_s + ', '
            cr_count += 1
          end
          msg += '}<br/>'

          msg += '[OPERATOR] : {'
          cr_count = 0
          Query.operators_labels.each do |k, l|
            if cr_count >= 5
              msg += '<br/>'
              cr_count = 0
            end
            msg += k + ':' + l + ', '
            cr_count += 1
          end

          raise msg.html_safe
        end
      end

      @query.column_names = parser.columns unless parser.columns.empty?

      @issues = @query.issues(:order => sort_clause, 
                              :include => [:assigned_to, :tracker, :priority, :category, :fixed_version]);

      if parser.onlyText || parser.onlyLink
        disp = String.new
        atr = parser.onlyText if parser.onlyText
        atr = parser.onlyLink if parser.onlyLink
        word = nil
        @issues.each do |issue|
          if issue.attributes.has_key?(atr)
            word = issue.attributes[atr].to_s
          else
            issue.custom_field_values.each do |cf|
              if 'cf_'+cf.custom_field.id.to_s == atr || cf.custom_field.name == atr
                word = cf.value
              end
            end
          end
          if word.nil?
            msg = 'attributes:'
            issue.attributes.each do |a|
              msg += a.to_s + ', '
            end
            raise msg.html_safe
            break
          end

          disp << ' ' if disp.size!=0
          if parser.onlyLink
            disp << link_to("#{word}", {:controller => "issues", :action => "show", :id => issue.id})
          else
            disp << textilizable(word)
          end
        end
      elsif parser.countFlag
        disp = @issues.size.to_s
      else
        disp = context_menu(issues_context_menu_path)
        disp << render(:partial => 'issues/list', :locals => {:issues => @issues, :query => @query});
      end

      return disp.html_safe
    end
  end
end
