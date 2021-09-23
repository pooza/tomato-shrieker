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

    def ignore_entry?(entry)
      return true if Entry.first(feed: id, title: NewsEntry.create_title(entry['title'], self))
      return super
    end

    def create_record(entry)
      return NewsEntry.create(entry, self)
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.select {|s| s.is_a?(GoogleNewsSource)}.each(&block)
    end
  end
end
