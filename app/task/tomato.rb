namespace :tomato do
  desc 'crawl'
  task run: [:crawl]

  desc 'crawl'
  task :crawl do
    Ginseng::CommandLine.new([
      File.join(TomatoToot::Environment.dir, 'bin/crawl.rb'),
    ]).exec
  end

  desc 'update timestamps'
  task :touch do
    Ginseng::CommandLine.new([
      File.join(TomatoToot::Environment.dir, 'bin/crawl.rb'),
      '--silence',
    ]).exec
  end

  desc 'clear timestamps'
  task :clean do
    Sequel.connect(TomatoToot::Environment.dsn)
    TomatoToot::Entry.dataset.destroy
  end
end

[:crawl, :run, :clean, :touch].each do |action|
  desc "alias of tomato:#{action}"
  task action => "tomato:#{action}"
end
