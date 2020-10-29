namespace :tomato do
  namespace :purge do
    desc 'delete old entries'
    task :run do
      TomatoShrieker::FeedSource.purge_all(echo: true)
    end

    desc 'delete old entries (dryrun)'
    task :dryrun do
      TomatoShrieker::FeedSource.purge_all(echo: true, dryrun: true)
    end
  end
end
