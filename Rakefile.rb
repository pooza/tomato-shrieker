ROOT_DIR = File.expand_path(__dir__)
$LOAD_PATH.push(File.join(ROOT_DIR, 'lib'))
ENV['BUNDLE_GEMFILE'] ||= File.join(ROOT_DIR, 'Gemfile')

require 'bundler/setup'

[:test, :touch, :clean].each do |action|
  desc "#{action} application"
  task action => ["app:#{action}"]
end

[:start, :stop, :restart].each do |action|
  desc "#{action} thin"
  task action => ["server:#{action}"]
end

namespace :app do
  task :test do
    require 'test/unit'
    Dir.glob(File.join(ROOT_DIR, 'test/*')).each do |t|
      require t
    end
  end

  task :touch do
    sh './loader.rb --silence'
  end

  task :clean do
    Dir.glob(File.join(ROOT_DIR, 'tmp/timestamps/*')) do |f|
      puts "delete #{f}"
      File.unlink(f)
    end
  end
end

namespace :server do
  [:start, :stop, :restart].each do |action|
    task action do
      sh "thin --config config/thin.yaml #{action}"
    end
  end
end
