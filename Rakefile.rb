ROOT_DIR = File.expand_path(__dir__)
$LOAD_PATH.push(File.join(ROOT_DIR, 'lib'))
ENV['BUNDLE_GEMFILE'] ||= File.join(ROOT_DIR, 'Gemfile')
ENV['SSL_CERT_FILE'] ||= File.join(ROOT_DIR, 'cert/cacert.pem')

require 'bundler/setup'
require 'tomato_toot'

[:run, :touch, :clean].each do |action|
  desc "alias of standalone:#{action}"
  task action => ["standalone:#{action}"]
end

[:start, :stop, :restart].each do |action|
  desc "alias of server:#{action}"
  task action => ["server:#{action}"]
end

desc 'test'
task :test do
  require 'test/unit'
  Dir.glob(File.join(ROOT_DIR, 'test/*')).each do |t|
    require t
  end
end

namespace :standalone do
  desc 'run standalone'
  task :run do
    sh './standalone.rb'
  end

  desc 'update timestamps'
  task :touch do
    sh './standalone.rb --silence'
  end

  desc 'clear timestamps'
  task :clean do
    Dir.glob(File.join(ROOT_DIR, 'tmp/timestamps/*')) do |f|
      puts "delete #{f}"
      File.unlink(f)
    end
  end
end

namespace :server do
  [:start, :stop, :restart].each do |action|
    desc "#{action} server"
    task action do
      sh "thin --config config/thin.yaml #{action}"
    end
  end

  desc 'show webhooks'
  task :hooks do
    require 'tomato-toot/webhook'
    TomatoToot::Webhook.all do |hook|
      puts hook.to_json
    end
  end
end
