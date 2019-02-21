namespace :tomato do
  task :test do
    ENV['TEST'] = TomatoToot::Package.name
    require 'test/unit'
    Dir.glob(File.join(TomatoToot::Environment.dir, 'test/*')).each do |t|
      require t
    end
  end
end
