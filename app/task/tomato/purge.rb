module TomatoShrieker
  extend Rake::DSL

  namespace :tomato do
    namespace :purge do
      desc 'delete old entries'
      task :run do
        FeedSource.purge_all(echo: true)
      end

      desc 'delete old entries (dryrun)'
      task :dryrun do
        FeedSource.purge_all(echo: true, dryrun: true)
      end
    end
  end
end
