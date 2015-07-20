# To change this template, choose Tools | Templates
# and open the template in the editor.

module WikiLists
  module RefIssues
    class Parser

      attr_reader :searchWordsS, :searchWordsD, :searchWordsW, :columns,
        :customQueryName, :customQueryId, :additionalFilter, :onlyText, :onlyLink, :countFlag
      def initialize(obj, args = nil, project = nil)
        parse_args obj, args, project if args
      end
      
      def parse_args(obj, args, project)
        args ||= []
        @searchWordsS = []
        @searchWordsD = []
        @searchWordsW = []
        @columns = []
        @restrictProject = nil
        @additionalFilter = []
        @onlyLink = nil
        @onlyText = nil
        @countFlag = nil
        args.each do |arg|
          arg.strip!;
          if arg=~/^\-([^\=:]*)([\=:])(.*)$/
            opt = $1
            sep = $2
            words = $3
          elsif arg=~/^\-([^\=:]*)$/
            opt = $1
            sep = nil
            words = defaultWords(obj).join('|')
          else
            @columns << get_column(arg)
            next
          end

          case opt
            when 's','sw','Dw','sDw','Dsw'
              @searchWordsS.push words_to_word_array(obj, words)
            when 'd','dw','Sw','Sdw','dSw'
              @searchWordsD.push words_to_word_array(obj, words)
            when 'w','sdw'
              @searchWordsW.push words_to_word_array(obj, words)
            when 'q'
              if sep
                @customQueryName = words
              else
                raise "no CustomQuery name:#{arg}"
              end
            when 'i'
              if sep
                @customQueryId = words
              else
                raise "no CustomQuery ID:#{arg}"
              end
            when 'p'
              if sep
                @restrictProject = Project.find(words)
              else
                @restrictProject = project
              end
            when 'f'
              if sep
                filter = ''
                operator = ''
                values = nil
                if words =~ /^([^ ]*) +([^ ]*)$/
                  filter = $1
                  operator = $2
                elsif words =~ /^([^ ]*) +([^ ]*) +(.*)$/
                  filter = $1
                  operator = $2
                  values = words_to_word_array(obj, $3)
                elsif words =~ /^(.*)=(.*)$/
                  filter = $1
                  operator = "="
                  values = words_to_word_array(obj, $2)
                else
                  filter = words
                  operator = "="
                  values = defaultWords(obj)
                end

                @additionalFilter << {:filter=>filter, :operator=>operator, :values=>values}
              else
                raise "no additional filter:#{arg}"
              end
            when 't'
              if sep
                @onlyText = words
              else
                @onlyText = 'subject'
              end
            when 'l'
              if sep
                @onlyLink = words
              else
                @onlyLink = 'subject'
              end
            when 'c'
              @countFlag = true
            else
              raise "unknown option:#{arg}"
          end
        end
      end
      
      def has_serch_conditions?
        return true if @customQueryId
        return true if @customQueryName 
        return true if @searchWordsS and !@searchWordsS.empty?
        return true if @searchWordsD and !@searchWordsD.empty?
        return true if @searchWordsW and !@searchWordsW.empty?
        return true if @additionalFilter and !@additionalFilter.empty?
        false
      end
      
      def query(project)
        # オプションにカスタムクエリがあればカスタムクエリを名前から取得
        if @customQueryId
          @query = IssueQuery.find_by_id(@customQueryId);
          @query = nil if @query && !@query.visible?
          raise "can not find CustomQuery ID:'#{@customQueryId}'" if !@query;
        elsif @customQueryName then
          cond = "project_id IS NULL"
          cond << " OR project_id = #{project.id}" if project
          cond = "(#{cond}) AND name = '#{@customQueryName}'";
          @query = IssueQuery.where(cond+" AND user_id=#{User.current.id}").first
          @query = IssueQuery.where(cond+" AND visibility = ?", Query::VISIBILITY_PUBLIC).first if !@query
          raise "can not find CustomQuery Name:'#{@customQueryName}'" if !@query;
        else
          @query = IssueQuery.new(:name => "_", :filters => {});
        end
      
        # Queryモデルを拡張
        overwrite_sql_for_field(@query);
        @query.available_filters["description"] = { :type => :text, :order => 8 };
        @query.available_filters["subjectdescription"] = { :type => :text, :order => 8 };
        @query.available_filters["fixed_version_id"] = { :type => :int};
        @query.available_filters["category_id"] = { :type => :int};
        @query.available_filters["parent_id"] = { :type => :int};

        if @restrictProject
          @query.project = @restrictProject
        end
        
        @query
      end

      def defaultWords(obj)
        words = []
        if obj.class == WikiContent  # Wikiの場合はページ名および別名を検索ワードにする
          words.push(obj.page.title); #ページ名
          redirects = WikiRedirect.where(["redirects_to=:s", {:s=>obj.page.title}]).all #別名query
          redirects.each do |redirect|
            words << redirect.title #別名
          end
        elsif obj.class == Issue  # チケットの場合はチケットsubjectを検索ワードにする
          words << obj.subject
        elsif obj.class == Journal && obj.journalized_type == "Issue"
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
        return name_sym if name =~ /^cf_/
        raise "unknown column:#{name}"
      end
      
      def overwrite_sql_for_field(query)
        def query.sql_for_field(field, operator, value, db_table, db_field, is_custom_filter=false)
          sql = ''
          case operator
          when "~" # monkey patched for ref_issues: originally treat single value  -> extend multiple value
            if db_field=='subjectdescription' then
              sql = "(";
              value.each do |v|
                sql << " OR " if sql != "(";
                sql << "LOWER(#{db_table}.subject) LIKE '%#{self.class.connection.quote_string(v.to_s.downcase)}%'";
                sql << " OR LOWER(#{db_table}.description) LIKE '%#{self.class.connection.quote_string(v.to_s.downcase)}%'";
              end
              sql << ")";
            else
              sql = "(";
              value.each do |v|
                sql << " OR " if sql != "(";
                sql << "LOWER(#{db_table}.#{db_field}) LIKE '%#{self.class.connection.quote_string(v.to_s.downcase)}%'";
              end
              sql << ")";
            end
          else
            sql = super(field, operator, value, db_table, db_field, is_custom_filter)
          end

          return sql
        end
      end

      def words_to_word_array(obj, words)
        word_array = words.split('|').collect do |word|
          word.strip!
          if word =~ /^\[(.*)\]$/
            raise "can not use reference '#{word}' except for issues." if obj.class != Issue
            atr = $1
            if obj.attributes.has_key?(atr)
              word = obj.attributes[atr]
            else
              obj.custom_field_values.each do |cf|
                if 'cf_'+cf.custom_field.id.to_s == atr || cf.custom_field.name == atr
                  word = cf.value
                end
              end
            end
          end
          word.to_s
        end
        word_array
      end

      def raise_filter_error(query)
        msg =  "<br/>failed add_filter: #{filterString}<br/>" +
            '[FILTER] : {'
        cr_count = 0
        query.available_filters.each do |k,f|
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
  end
end
