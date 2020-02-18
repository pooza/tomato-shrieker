namespace :tomato do
  desc 'crawl (silence)'
  task :run do
    system File.join(TomatoToot::Environment.dir, 'bin/crawl.rb')
  end

  desc 'crawl'
  task :crawl do
    sh File.join(TomatoToot::Environment.dir, 'bin/crawl.rb')
  end

  desc 'update timestamps'
  task :touch do
    sh "#{File.join(TomatoToot::Environment.dir, 'bin/crawl.rb')} --silence"
  end

  desc 'clear timestamps'
  task :clean do
    Dir.glob(File.join(TomatoToot::Environment.dir, 'tmp/timestamps/*')) do |f|
      puts "delete #{f}"
      File.unlink(f)
    end
  end
end

[:crawl, :run, :clean, :touch].each do |action|
  desc "alias of tomato:#{action}"
  task action => "tomato:#{action}"
end
