module TomatoShrieker
  class GoogleNewsSource < FeedSource
    def uri
      uri = Ginseng::URI.parse(self['/source/news'])
      uri ||= Ginseng::URI.parse(self['/source/google_news'])
      return nil unless uri&.absolute?
      return uri
    end

    def unique_title?
      return true
    end

    def template_name
      return 'title'
    end

    def fetch
      return enum_for(__method__) unless block_given?
      feedjira.entries.sort_by {|entry| entry.published.to_f}.each do |entry|
        next if Entry.first(feed: id, title: NewsEntry.create_title(entry['title'], self))
        next if keyword && !hot_entry?(entry)
        next if negative_keyword && negative_entry?(entry)
        next unless record = NewsEntry.create(entry, self)
        yield record
      rescue => e
        logger.error(error: e)
      end
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.select {|s| s.is_a?(GoogleNewsSource)}.each(&block)
    end
  end
end
