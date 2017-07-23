module RedmineWikiLists::RefIssues
  Redmine::WikiFormatting::Macros.register do
    desc 'Displays a list of referer issues.'
    macro :ref_issues do |obj, args|
      parser = nil

      begin
        parser = RedmineWikiLists::RefIssues::Parser.new(obj, args, @project)
      rescue => err_msg
        attributes = IssueQuery.available_columns
        msg = <<-TEXT
- <br>parameter error: #{err_msg}<br>
#{err_msg.backtrace[0]}<br><br>
usage: {{ref_issues([option].., [column]..)}}<br>
<br>[options]<br>
-i=CustomQueryID : specify custom query by id<br>
-q=CustomQueryName : specify custom query by name<br>
-p[=identifier] : restrict project<br>
-f:FILTER[=WORD[|WORD...]] : additional filter<br>
-t[=column] : display text<br>
-l[=column] : display linked text<br>
-c : count issues<br>
-0 : no display if no issues
<br>[columns]<br> {
TEXT

        while attributes
          attributes[0...5].each do |a|
            msg += a.name.to_s + ', '
          end

          attributes = attributes[5..-1]
          msg += '<br>' if attributes
        end

        msg += 'cf_* }<br/>'
        raise msg.html_safe
      end

      begin
        unless parser.has_search_conditions? # 検索条件がなにもなかったら
          # 検索するキーワードを取得する
          parser.search_words_w << parser.default_words(obj)
        end

        @query = parser.query @project

        extend SortHelper
        extend QueriesHelper
        extend IssuesHelper

        sort_clear
        sort_init(@query.sort_criteria.empty? ? [['id', 'desc']] : @query.sort_criteria)
        sort_update(@query.sortable_columns)
        #@issue_count_by_group = @query.issue_count_by_group

        parser.search_words_s.each do |words|
          @query.add_filter('subject', '~', words)
        end

        parser.search_words_d.each do |words|
          @query.add_filter('description', '~', words)
        end

        parser.search_words_w.each do |words|
          @query.add_filter('subjectdescription', '~', words)
        end

        models =
            {'tracker' => Tracker,
             'category' => IssueCategory,
             'status' => IssueStatus,
             'assigned_to' => User,
             'author' => User,
             'version' => Version,
             'project' => Project}
        ids =
            {'tracker' => 'tracker_id',
             'category' => 'category_id',
             'status' => 'status_id',
             'assigned_to' => 'assigned_to_id',
             'author' => 'author_id',
             'version' => 'fixed_version_id',
             'project' => 'project_id'}
        attributes =
            {'tracker' => 'name',
             'category' => 'name',
             'status' => 'name',
             'assigned_to' => 'login',
             'author' => 'login',
             'version' => 'name',
             'project' => 'name'}

        parser.additional_filter.each do |filter_set|
          filter = filter_set[:filter]
          operator = filter_set[:operator]
          values = filter_set[:values]

          if models.has_key?(filter)
            unless values.nil?
              tgt_objs = []
              values.each do |value|
                tgt_obj = models[filter].find_by(attributes[filter]=>value)
                raise "- can not resolve '#{value}' in #{models[filter].to_s}.#{attributes[filter]} " if tgt_obj.nil?
                tgt_objs << tgt_obj.id.to_s
              end
              values = tgt_objs
            end
            filter = ids[filter]
          end

          res = @query.add_filter(filter , operator, values)

          if res.nil?
            filter_str = filter_set[:filter] + filter_set[:operator] + filter_set[:values].join('|')
            cr_count = 0
            msg = "- failed add_filter: #{filter_str}<br><br>[FILTER]<br>"

            @query.available_filters.each do |k,f|
              if cr_count >= 5
                msg += '<br>'
                cr_count = 0
              end

              msg += k.to_s + ', '
              cr_count += 1
            end

            models.each do |k, _m|
              if cr_count >= 5
                msg += '<br>'
                cr_count = 0
              end

              msg += k.to_s + ', '
              cr_count += 1
            end

            msg += '<br><br>[OPERATOR]<br>'
            cr_count = 0

            Query.operators_labels.each do |k, l|
              if cr_count >= 5
                msg += '<br>'
                cr_count = 0
              end

              msg += k + ':' + l + ', '
              cr_count += 1
            end

            msg += '<br>'
            raise msg.html_safe
          end
        end

        @query.column_names = parser.columns unless parser.columns.empty?
        @issues = @query.issues(order: sort_clause)

        if parser.zero_flag && @issues.size == 0
          disp = ''
        elsif parser.only_text || parser.only_link
          disp = ''
          atr = parser.only_text if parser.only_text
          atr = parser.only_link if parser.only_link
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

            if parser.only_link
              disp << link_to("#{word}", issue_path(issue))
            else
              disp << textilizable(word, object: issue)
            end
          end
        elsif parser.count_flag
          disp = @issues.size.to_s
        else
          if params[:format] == 'pdf'
            disp = render(partial: 'issues/list.html', locals: {issues: @issues, query: @query})
          else
            if method(:context_menu).parameters.size > 0
              disp = context_menu(issues_context_menu_path) # < redmine 3.3.x
            else
              disp = context_menu.to_s # >= redmine 3.4.0
            end
            disp << render(partial: 'issues/list', locals: {issues: @issues, query: @query})
          end
        end

        disp.html_safe
      rescue => err_msg
        msg = "#{err_msg}"
        if msg[0] != '-'
          err_msg.backtrace.each do |backtrace|
            msg << "<br>#{backtrace}"
          end
        end
        raise msg.html_safe
      end
    end
  end
end
