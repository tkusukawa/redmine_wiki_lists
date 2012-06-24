# To change this template, choose Tools | Templates
# and open the template in the editor.

module WikiLists
  module RefIssues
    class Parser
      COLUMNS = [:project, :tracker, :parent, :status, :priority, :subject,
        :author, :assigned_to, :updated_on, :category, :fixed_version, 
        :start_date, :due_date, :estimated_hours, :done_ratio, :created_on]
      
      attr_reader :searchWordsS, :searchWordsD, :searchWordsW, :columns,
        :customQueryName, :customQueryId
      def initialize(args = nil, project = nil)
        parse_args args, project if args
      end
      
      def parse_args(args, project)
        args ||= []
        @searchWordsS = []
        @searchWordsD = []
        @searchWordsW = []
        @columns = []
        @restrictProject = nil
        args.each do |arg|
          arg.strip!;
          if arg=~/^\-([^\=]*)(\=.*)?$/
            case $1
            when 's','sw','Dw','sDw','Dsw'              
              @searchWordsS.push get_words(arg)
            when 'd','dw','Sw','Sdw','dSw'             
              @searchWordsD.push get_words(arg)
            when 'w','sdw'              
              @searchWordsW.push get_words(arg)
            when 'q'
              if arg=~/^[^\=]+\=(.*)$/
                @customQueryName = $1;
              else
                raise "no CustomQuery name:#{arg}"
              end
            when 'i'
              if arg=~/^[^\=]+\=(.*)$/
                @customQueryId = $1;
              else
                raise "no CustomQuery ID:#{arg}"
              end
            when 'p'
              if arg=~/^[^\=]+\=(.*)$/
                @restrictProject = Project.find $1;
              else
                @restrictProject = project
              end
            else
              raise "unknown option:#{arg}"
            end
          else
            @columns << get_column(arg)            
          end
        end        
      end
      
      def has_serch_conditions?
        return true if @customQueryId
        return true if @customQueryName 
        return true if @searchWordsS and !@searchWordsS.empty?
        return true if @searchWordsD and !@searchWordsD.empty?
        return true if @searchWordsW and !@searchWordsW.empty?
        false
      end
      
      def query(project)
        # オプションにカスタムクエリがあればカスタムクエリを名前から取得
        if @customQueryId
          @query = Query.find_by_id(@customQueryId);
          @query = nil if !@query.visible?
          raise "can not find CustomQuery ID:'#{@customQueryId}'" if !@query;
        elsif @customQueryName then
          cond = "project_id IS NULL"
          cond << " OR project_id = #{project.id}" if project
          cond = "(#{cond}) AND name = '#{@customQueryName}'";
          @query = Query.find(:first, :conditions=>cond+" AND user_id=#{User.current.id}")
          @query = Query.find(:first, :conditions=>cond+" AND is_public=TRUE") if !@query
          raise "can not find CustomQuery Name:'#{@customQueryName}'" if !@query;
        else
          @query = Query.new(:name => "_", :filters => {});
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
        
      private
        
      def get_words(arg)
        if arg=~/^[^\=]+\=(.*)$/
          $1.split('|')
        else
          raise "need words divided by '|':#{arg}>"
        end
      end
      
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
