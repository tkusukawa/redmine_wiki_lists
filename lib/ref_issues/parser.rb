# To change this template, choose Tools | Templates
# and open the template in the editor.

module WikiLists
  module RefIssues
    class Parser
      COLUMNS = [:project, :tracker, :parent, :status, :priority, :subject,
        :author, :assigned_to, :updated_on, :category, :fixed_version, 
        :start_date, :due_date, :estimated_hours, :done_ratio, :created_on]
      
      attr_reader :searchWordsS, :searchWordsD, :searchWordsW, :columns,
        :customQueryName, :customQueryId, :additionalFilter, :onlyLink
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

          if words=~/^\[(.*)\]$/
            atr = $1
            if obj.attributes.has_key?(atr)
              words = obj.attributes[atr]
            else
              obj.custom_field_values.each do |cf|
                if 'cf_'+cf.custom_field.id.to_s == atr || cf.custom_field.name == atr
                  words = cf.value
                end
              end
            end
          end

          case opt
            when 's','sw','Dw','sDw','Dsw'
              @searchWordsS.push words.split('|')
            when 'd','dw','Sw','Sdw','dSw'
              @searchWordsD.push words.split('|')
            when 'w','sdw'
              @searchWordsW.push words.split('|')
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
                @additionalFilter << words
              else
                raise "no additional filter:#{arg}"
              end
            when 'l'
              if sep
                @onlyLink = words
              else
                @onlyLink = 'subject'
              end
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
          @query = nil if !@query.visible?
          raise "can not find CustomQuery ID:'#{@customQueryId}'" if !@query;
        elsif @customQueryName then
          cond = "project_id IS NULL"
          cond << " OR project_id = #{project.id}" if project
          cond = "(#{cond}) AND name = '#{@customQueryName}'";
          @query = IssueQuery.find(:first, :conditions=>cond+" AND user_id=#{User.current.id}")
          @query = IssueQuery.find(:first, :conditions=>cond+" AND is_public=TRUE") if !@query
          raise "can not find CustomQuery Name:'#{@customQueryName}'" if !@query;
        else
          @query = IssueQuery.new(:name => "_", :filters => {});
        end
      
        # Queryモデルを拡張
        overwrite_sql_for_field(@query);
        @query.available_filters["description"] = { :type => :text, :order => 8 };
        @query.available_filters["subjectdescription"] = { :type => :text, :order => 8 };

        if @restrictProject
          @query.project = @restrictProject
        end
        
        @query
      end

      def defaultWords(obj)
        words = []
        if obj.class == WikiContent  # Wikiの場合はページ名および別名を検索ワードにする
          words.push(obj.page.title); #ページ名
          redirects = WikiRedirect.find(:all, :conditions=>["redirects_to=:s", {:s=>obj.page.title}]); #別名query
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
        return name_sym if COLUMNS.include?(name_sym)
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
                sql << "LOWER(#{db_table}.subject) LIKE '%#{connection.quote_string(v.to_s.downcase)}%'";
                sql << " OR LOWER(#{db_table}.description) LIKE '%#{connection.quote_string(v.to_s.downcase)}%'";
              end
              sql << ")";
            else
              sql = "(";
              value.each do |v|
                sql << " OR " if sql != "(";
                sql << "LOWER(#{db_table}.#{db_field}) LIKE '%#{connection.quote_string(v.to_s.downcase)}%'";
              end
              sql << ")";
            end
          else
            sql = super(field, operator, value, db_table, db_field, is_custom_filter)
          end

          return sql
        end
      end
    end
  end
end
