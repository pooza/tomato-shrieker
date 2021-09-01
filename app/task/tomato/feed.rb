module TomatoShrieker
  extend Rake::DSL

  namespace :tomato do
    namespace :feed do
      desc 'entry summary (for "multi_entries" feed source)'
      task :summary do
        FeedSource.all.select(&:multi_entries?).each do |source|
          puts ({
            id: source.id,
            category: source.category,
            entries: source.multi_entries.map do |entry|
              {published: entry.published, title: entry.title}
            end,
          }).to_yaml
        end
      end
    end
  end
end
