module RedmineWikiLists::IssueNameLink
  Redmine::WikiFormatting::Macros.register do
    desc 'Make a link of a issue by its subject.'
    macro :issue_name_link do |obj, args|
      out = ''

      begin
        raise '- no parameters' if args.count.zero?
        raise '- too many parameters' if args.count > 1
        arg = args.shift
        arg.strip!

        if arg =~ /\A([^:]*):([^:]*)\z/
          prj = Project.find_by_identifier($1)
          prj ||= Project.find_by_name($1)
          raise "- project:#{$1} is not found." unless prj
          arg = $2
        else
          prj = obj.project
        end

        if arg =~ /\A([^\|]*)\|([^\|]*)\z/
          name = $1
          disp = $2
        else
          name = arg
          disp = arg
        end

        issue = Issue.where(project_id: prj.id, subject: name).first
        raise "- issue:#{name} is not found in prj:#{prj.to_s}" unless issue
        Issue.find_by_subject(name)
        out << link_to("#{disp}", issue_path(issue))
      rescue => err_msg
        raise <<-TEXT.html_safe
Parameter error: #{err_msg}<br>
Usage: {{issue_name_link([project_name:]issue_subject[|description])}}
TEXT
      end

      out.html_safe
    end
  end
end
