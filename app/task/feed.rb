namespace :tomato do
  namespace :feed do
    desc 'entry summary (for "multi_entries" feed source)'
    task :summary do
      TomatoShrieker::Source.all do |source|
        next unless source.is_a?(TomatoShrieker::FeedSource)
        next unless source.multi_entries?
        puts YAML.dump(
          id: source.id,
          category: source.category,
          entries: source.multi_entries.map do |entry|
            {published: entry.published, title: entry.title}
          end,
        )
      end
    end
  end
end
