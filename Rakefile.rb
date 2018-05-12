ROOT_DIR = File.expand_path(__dir__)
$LOAD_PATH.push(File.join(ROOT_DIR, 'lib'))
ENV['BUNDLE_GEMFILE'] ||= File.join(ROOT_DIR, 'Gemfile')

require 'bundler/setup'

desc 'touch'
task :touch do
  sh './loader.rb --silence'
end

desc 'clean'
task :clean do
  Dir.glob(File.join(ROOT_DIR, 'tmp/timestamps/*')) do |f|
    puts "delete #{f}"
    File.unlink(f)
  end
end
