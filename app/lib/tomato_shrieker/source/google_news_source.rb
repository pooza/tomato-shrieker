module TomatoShrieker
  class GoogleNewsSource < FeedSource
    def uri
      uri = Ginseng::URI.parse(self['/source/google_news'])
      return nil unless uri&.absolute?
      return uri
    end

    def unique_title?
      return true
    end

    def fetch
      return enum_for(__method__) unless block_given?
      feedjira.entries.sort_by {|entry| entry.published.to_f}.each do |v|
        next if Entry.first(feed: id, title: NewsEntry.create_title(v['title']))
        next unless entry = NewsEntry.create(v, self)
        yield entry
      end
    end

    def self.all
      return enum_for(__method__) unless block_given?
      Source.all do |source|
        next unless source.is_a?(GoogleNewsSource)
        yield source
      end
    end
  end
end
