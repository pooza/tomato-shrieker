namespace :tomato do
  namespace :purge do
    desc 'delete old entries'
    task :run do
      TomatoShrieker::Source.all do |source|
        next unless source.is_a?(TomatoShrieker::FeedSource)
        date = source.purge
        puts "#{source.id}: purge (older than #{date})" if date
      end
    end

    desc 'delete old entries (dryrun)'
    task :dryrun do
      TomatoShrieker::Source.all do |source|
        next unless source.is_a?(TomatoShrieker::FeedSource)
        date = source.purge(dryrun: true)
        puts "#{source.id}: purge dryrun (older than #{date})" if date
      end
    end
  end
end
