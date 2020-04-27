namespace :tomato do
  desc 'crawl'
  task run: [:crawl]

  desc 'crawl'
  task :crawl do
    command = Ginseng::CommandLine.new([
      File.join(TomatoToot::Environment.dir, 'bin/crawl.rb'),
    ])
    command.exec
  end

  desc 'update timestamps'
  task :touch do
    command = Ginseng::CommandLine.new([
      File.join(TomatoToot::Environment.dir, 'bin/crawl.rb'),
      '--silence',
    ])
    command.exec
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
