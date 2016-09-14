Rails.configuration.to_prepare do
  require_dependency 'redmine_wiki_lists/issue_name_link'
  require_dependency 'redmine_wiki_lists/ref_issues/parser'
  require_dependency 'redmine_wiki_lists/ref_issues'
  require_dependency 'redmine_wiki_lists/wiki_list'
end

Redmine::Plugin.register :redmine_wiki_lists do
  name 'Redmine Wiki Lists plugin'
  author 'Tomohisa Kusukawa'
  description 'wiki macros to display lists of issues.'
  version '0.0.6'
  url 'http://www.r-labs.org/projects/wiki_lists/wiki/Wiki_Lists'
  author_url 'http://bitbucket.org/tkusukawa'
end
