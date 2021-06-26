desc 'test all'
task :test do
  TomatoShrieker::TestCase.load((ARGV.first&.split(/[^[:word:],]+/) || [])[1])
end
