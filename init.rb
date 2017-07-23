plugin_name = :redmine_wiki_lists

Rails.configuration.to_prepare do
  %w{issue_name_link ref_issues/parser ref_issues wiki_list}.each do |file_name|
    require_dependency "#{plugin_name}/#{file_name}"
  end
end

Redmine::Plugin.register plugin_name do
  name 'Redmine Wiki Lists plugin'
  author 'Tomohisa Kusukawa'
  description 'wiki macros to display lists of issues.'
  version '0.0.9'
  url 'https://www.r-labs.org/projects/wiki_lists/wiki/Wiki_Lists_en'
  author_url 'https://github.com/tkusukawa/'
end
