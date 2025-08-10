module TomatoShrieker
  class GoogleNewsSource < FeedSource
    def uri
      if self['/source/news/phrase']
        uri = Ginseng::URI.parse(config['/google/news/urls/root'])
        values = uri.query_values || {}
        values['q'] = self['/source/news/phrase']
        uri.query_values = values
      else
        uri = Ginseng::URI.parse(self['/source/news/url'])
      end
      return uri.normalize if uri&.absolute?
    end

    def phrase
      return self['/source/news/phrase'] || uri.query_values['q']
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.select {|s| s.is_a?(self)}.each(&block)
    end
  end
end
