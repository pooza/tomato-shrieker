module TomatoShrieker
  extend Rake::DSL

  desc 'test all'
  task :test do
    TestCase.load
  end
end
