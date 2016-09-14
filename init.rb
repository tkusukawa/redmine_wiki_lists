require 'redmine'

Dir::foreach(File.join(File.dirname(__FILE__), 'lib', 'redmine_wiki_lists')) do |file|
  next unless /\.rb$/ =~ file
  require_dependency file
end

Redmine::Plugin.register :redmine_wiki_lists do
  name 'Redmine Wiki Lists plugin'
  author 'Tomohisa Kusukawa'
  description 'wiki macros to display lists of issues.'
  version '0.0.6'
  url 'http://www.r-labs.org/projects/wiki_lists/wiki/Wiki_Lists'
  author_url 'http://bitbucket.org/tkusukawa'
end
