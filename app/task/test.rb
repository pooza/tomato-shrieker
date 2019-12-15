desc 'test all'
task :test do
  ENV['TEST'] = TomatoToot::Package.name
  require 'test/unit'
  Dir.glob(File.join(TomatoToot::Environment.dir, 'test/*.rb')).each do |t|
    require t
  end
end