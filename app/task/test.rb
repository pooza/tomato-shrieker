require 'pp'

desc 'test all'
task :test do
  TomatoShrieker::TestCase.load
end
