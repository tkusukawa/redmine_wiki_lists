# To change this template, choose Tools | Templates
# and open the template in the editor.

module RedmineWikiLists
  module RefIssues
    class Parser
      attr_reader :search_words_s, :search_words_d, :search_words_w, :columns,
                  :custom_query_name, :custom_query_id, :additional_filter, :only_text, :only_link, :count_flag, :zero_flag

      def initialize(obj, args = nil, project = nil)
        parse_args(obj, args, project) if args
      end

      def parse_args(obj, args, project)
        args ||= []
        @project = project
        @search_words_s = []
        @search_words_d = []
        @search_words_w = []
        @columns = []
        @restrict_project = nil
        @additional_filter = []
        @only_link = nil
        @only_text = nil
        @count_flag = nil
        @zero_flag = nil

        args.each do |arg|
          arg.strip!
          arg.gsub!('&gt;', '>')
          arg.gsub!('&lt;', '<')

          if arg=~/\A\-([^\=:]*)\s*([\=:])\s*(.*)\z/
            opt = $1.strip
            sep = $2.strip
            words = $3.strip
          elsif arg=~/\A\-([^\=:]*)\z/
            opt = $1.strip
            sep = nil
            words = default_words(obj).join('|')
          else
            @columns << get_column(arg)
            next
          end

          case opt
            when 's','sw','Dw','sDw','Dsw'
              @search_words_s.push words_to_word_array(obj, words)
            when 'd','dw','Sw','Sdw','dSw'
              @search_words_d.push words_to_word_array(obj, words)
            when 'w','sdw'
              @search_words_w.push words_to_word_array(obj, words)
            when 'q'
              if sep
                @custom_query_name = words
              else
                raise "- no CustomQuery name:#{arg}"
              end
            when 'i'
              if sep
                @custom_query_id = words
              else
                raise "- no CustomQuery ID:#{arg}"
              end
            when 'p'
              @restrict_project = sep ? Project.find(words) : project
            when 'f'
              if sep
                filter = ''
                operator = ''
                values = nil

                if words =~ /\A([^\s]*)\s+([^\s]*)\z/
                  filter = $1
                  operator = refer_field(obj, $2)
                elsif words =~ /\A([^\s]*)\s+([^\s]*)\s+(.*)\z/
                  filter = $1
                  operator = refer_field(obj, $2)
                  values = words_to_word_array(obj, $3)
                elsif words =~ /\A(.*)=(.*)\z/
                  filter = $1
                  operator = '='
                  values = words_to_word_array(obj, $2)
                else
                  filter = words
                  operator = '='
                  values = default_words(obj)
                end

                @additional_filter << {:filter=>filter, :operator=>operator, :values=>values}
              else
                raise "- no additional filter:#{arg}"
              end
            when 't'
              @only_text = sep ? words : 'subject'
            when 'l'
              @only_link = sep ? words : 'subject'
            when 'c'
              @count_flag = true
            when '0'
              @zero_flag = true
            else
              raise "- unknown option:#{arg}"
          end
        end
      end

      def has_search_conditions?
        return true if @custom_query_id
        return true if @custom_query_name
        return true if @search_words_s.present?
        return true if @search_words_d.present?
        return true if @search_words_w.present?
        return true if @additional_filter.present?
        false
      end

      def query(project)
        # オプションにカスタムクエリがあればカスタムクエリを名前から取得
        if @custom_query_id
          @query = IssueQuery.visible.find_by_id(@custom_query_id)
          raise "- can not find CustomQuery ID:'#{@custom_query_id}'" unless @query
        elsif @custom_query_name then
          cond = 'project_id IS NULL'
          cond << " OR project_id = #{project.id}" if project
          cond = "(#{cond}) AND name = '#{@custom_query_name}'"
          @query = IssueQuery.where(cond).where(user_id: User.current.id).first
          @query = IssueQuery.where(cond).where(visibility: Query::VISIBILITY_PUBLIC).first unless @query
          raise "- can not find CustomQuery Name:'#{@custom_query_name}'" unless @query
        else
          @query = IssueQuery.new(name: '_', filters: {})
        end

        @query.user = User.current
        if @restrict_project
          @query.project = @restrict_project
        end

        # Queryモデルを拡張
        overwrite_sql_for_field(@query)
        @query.available_filters['description'] = {type: :text, order: 8}
        @query.available_filters['subjectdescription'] = {type: :text, order: 8}
        @query.available_filters['fixed_version_id'] = {type: :int}
        @query.available_filters['category_id'] = {type: :int}
        @query.available_filters['parent_id'] = {type: :int}
        @query.available_filters['id'] = {type: :int}
        @query.available_filters['treated'] = {type: :date}

        @query
      end

      def default_words(obj)
        words = []

        if obj.class == WikiContent  # Wikiの場合はページ名および別名を検索ワードにする
          words.push(obj.page.title) #ページ名
          redirects = WikiRedirect.where(redirects_to: obj.page.title) #別名query

          redirects.each do |redirect|
            words << redirect.title #別名
          end
        elsif obj.class == Issue  # チケットの場合はチケットsubjectを検索ワードにする
          words << obj.subject
        elsif obj.class == Journal && obj.journalized_type == 'Issue'
          # チケットコメントの場合もチケット番号表記を検索ワードにする
          words << '#'+obj.journalized_id.to_s
        end

        words
      end

      private

      def get_column(name)
        name_sym = name.to_sym

        IssueQuery.available_columns.each do |col|
          return name_sym if name_sym == col.name.to_sym
        end

        return :assigned_to if name_sym == :assigned
        return :updated_on if name_sym == :updated
        return :created_on if name_sym == :created
        return name_sym if name =~ /\Acf_/
        raise "- unknown column:#{name}"
      end

      # @todo Стремный патч, который сделан из-за отсутствия поминимания как работать с Query. По сути, надо патчить IssueQuery
      def overwrite_sql_for_field(query)
        def query.sql_for_field(field, operator, value, db_table, db_field, is_custom_filter=false)
          if operator == '~'
            # monkey patched for ref_issues: originally treat single value  -> extend multiple value
            if db_field=='subjectdescription'
              sql = '('

              value.each do |v|
                sql << ' OR ' if sql != '('
                sql << "LOWER(#{db_table}.subject) LIKE '%#{self.class.connection.quote_string(v.to_s.downcase)}%'"
                sql << " OR LOWER(#{db_table}.description) LIKE '%#{self.class.connection.quote_string(v.to_s.downcase)}%'"
              end

              sql << ')'
              return sql
            else
              sql = '('

              value.each do |v|
                sql << ' OR ' if sql != '('
                sql << "LOWER(#{db_table}.#{db_field}) LIKE '%#{self.class.connection.quote_string(v.to_s.downcase)}%'"
              end

              sql << ')'
              return sql
            end
          elsif operator == '=='
            sql = '('

            value.each do |v|
              sql << ' OR ' if sql != '('
              sql << "LOWER(#{db_table}.#{db_field}) = '#{self.class.connection.quote_string(v.to_s.downcase)}'"
            end

            sql << ')'
            return sql
          elsif db_field == 'treated'
            raise "- too many values for treated" if value.length > 2
            raise "- too few values for treated" if value.length < 2
            start_date = value[0]
            end_date = value[1]
            if operator =~ /^\d+$/
              user = operator
            else
              user_obj = User.find_by_login(operator)
              raise "- can not find user <#{operator}>" if user_obj.nil?
              user = user_obj.id.to_s
            end

            sql =  '('
            sql << "  (issues.author_id = #{user}"
            sql << "   AND (CAST(issues.created_on AS DATE) BETWEEN '#{start_date}' AND '#{end_date}'))"
            sql << "  OR ("
            sql << "    (select count(*) from journals where journalized_type = 'Issue' AND journalized_id = issues.id"
            sql << "      AND journals.user_id = #{user}"
            sql << "      AND (CAST(journals.created_on AS DATE) BETWEEN '#{start_date}' AND '#{end_date}')"
            sql << "    ) > 0"
            sql << "  )"
            sql << ')'
            return sql
          end

          return super(field, operator, value, db_table, db_field, is_custom_filter)
        end
      end

      def words_to_word_array(obj, words)
        words.split('|').collect do |word|
          word.strip!
          refer_field(obj, word)
        end
      end

      def refer_field(obj, word)
        if word =~ /\[current_user\]/
          return User.current.login
        end

        if word =~ /\[current_user_id\]/
          return User.current.id.to_s
        end

        if word =~ /\[current_project_id\]/
          return @project.id.to_s
        end

        if word =~ /\[(.*)days_ago\]/
          return (Date.today - $1.to_i).strftime("%Y-%m-%d")
        end

        if word =~ /\A\[(.*)\]\z/
          raise "- can not use reference '#{word}' except for issues." if obj.class != Issue
          atr = $1

          if obj.attributes.has_key?(atr)
            word = obj.attributes[atr]
          else
            obj.custom_field_values.each do |cf|
              if 'cf_' + cf.custom_field.id.to_s == atr || cf.custom_field.name == atr
                word = cf.value
              end
            end
          end
        end
        return word.to_s
      end
    end
  end
end
