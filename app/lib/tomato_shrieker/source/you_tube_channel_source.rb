module TomatoShrieker
  class YouTubeChannelSource < FeedSource
    def feed_uri
      uri = Ginseng::URI.parse(config['/youtube/urls/feed'])
      values = uri.query_values || {}
      values['channel_id'] = channel_id
      uri.query_values = values
      return uri.normalize if uri&.absolute?
    end

    alias uri feed_uri

    def channel_uri
      if url = self['/source/youtube/channel/url']
        uri = Ginseng::YouTube::ChannelURI.parse(url)
      elsif id = self['/source/youtube/channel/id']
        uri = Ginseng::YouTube::ChannelURI.parse(config['/youtube/urls/root'])
        uri.id = id
      end
      return uri.normalize if uri&.absolute?
    end

    def channel_id
      if url = self['/source/youtube/channel/url']
        return Ginseng::YouTube::ChannelURI.parse(url).id
      elsif id = self['/source/youtube/channel/id']
        return id
      end
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.select {|s| s.is_a?(self)}.each(&block)
    end
  end
end
