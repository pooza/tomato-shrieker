ROOT_DIR = File.expand_path(__dir__)
$LOAD_PATH.push(File.join(ROOT_DIR, 'lib'))
ENV['BUNDLE_GEMFILE'] ||= File.join(ROOT_DIR, 'Gemfile')

require 'bundler/setup'

desc 'clear timestamps (obsosleted: 1.x compatible)'
task clean: ['standalone:clean']

desc 'update timestamps (obsosleted: 1.x compatible)'
task touch: ['standalone:touch']

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
    TomatoToot::Webhook.all do |webhook|
      puts webhook.to_json
    end
  end
end
