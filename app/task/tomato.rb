namespace :tomato do
  desc 'crawl'
  task run: [:crawl]

  desc 'crawl'
  task :crawl do
    sh File.join(TomatoToot::Environment.dir, 'bin/crawl.rb').to_s
  end

  desc 'update timestamp'
  task :touch do
    sh "#{File.join(TomatoToot::Environment.dir, 'bin/crawl.rb')} --silence"
  end

  desc 'clear entries'
  task :clean do
    Sequel.connect(TomatoToot::Environment.dsn)
    TomatoToot::Entry.clean
  end
end

[:crawl, :run, :clean, :touch].each do |action|
  desc "alias of tomato:#{action}"
  task action => "tomato:#{action}"
end
