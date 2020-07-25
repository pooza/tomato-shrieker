desc 'test all'
task :test do
  ENV['TEST'] = TomatoShrieker::Package.name
  require 'test/unit'
  Sequel.connect(TomatoShrieker::Environment.dsn)
  Dir.glob(File.join(TomatoShrieker::Environment.dir, 'test/*.rb')).sort.each do |t|
    require t
  end
end
