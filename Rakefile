dir = File.expand_path(__dir__)
$LOAD_PATH.unshift(File.join(dir, 'lib'))
ENV['BUNDLE_GEMFILE'] ||= File.join(dir, 'Gemfile')
ENV['SSL_CERT_FILE'] ||= File.join(dir, 'cert/cacert.pem')
ENV['RAKE_MODULE'] = 'TomatoToot'

require 'bundler/setup'
require 'tomato_toot'

desc 'test all'
task test: ['tomato:test']

[:crawl, :run, :clean, :touch].each do |action|
  desc "alias of tomato:#{action}"
  task action => "tomato:#{action}"
end

['Ginseng', 'TomatoToot'].each do |prefix|
  Dir.glob(File.join("#{prefix}::Environment".constantize.dir, 'lib/task/*.rb')).each do |f|
    require f
  end
end
