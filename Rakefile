dir = File.expand_path(__dir__)
$LOAD_PATH.unshift(File.join(dir, 'lib'))
ENV['BUNDLE_GEMFILE'] ||= File.join(dir, 'Gemfile')

require 'bundler/setup'
require 'tomato_toot'

[:crawl, :run, :clean, :touch].each do |action|
  desc "alias of tomato:#{action}"
  task action => "tomato:#{action}"
end

Dir.glob(File.join(TomatoToot::Environment.dir, 'lib/task/*.rb')).each do |f|
  require f
end
