namespace :tomato do
  desc 'crawl'
  task :crawl do
    sh File.join(TomatoShrieker::Environment.dir, 'bin/crawl.rb').to_s
  end

  desc 'update timestamps'
  task :touch do
    sh "#{File.join(TomatoShrieker::Environment.dir, 'bin/crawl.rb')} --silence"
  end

  desc 'clear entries'
  task :clean do
    TomatoShrieker::Entry.dataset.destroy
  end
end

[:crawl, :clean, :touch].each do |action|
  desc "alias of tomato:#{action}"
  task action => "tomato:#{action}"
end
