require 'redmine'

Dir::foreach(File.join(File.dirname(__FILE__), 'lib')) do |file|
  next unless /\.rb$/ =~ file
  require file
end

Redmine::Plugin.register :redmine_wiki_lists do
  name 'Redmine Wiki Lists plugin'
  author 'Tomohisa Kusukawa'
  description 'wiki macros to display lists of contents.'
  version '0.0.1'
  url 'https://bitbucket.org/kusu/redmine_wiki_lists'
end
