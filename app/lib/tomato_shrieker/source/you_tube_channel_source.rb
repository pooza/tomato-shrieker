module TomatoShrieker
  class YouTubeChannelSource < FeedSource
    def feed_uri
      uri = Ginseng::URI.parse(config['/youtube/urls/feed'])
      uri.query_values['channel_id'] = channel_id
      return uri
    end

    alias uri feed_uri

    def channel_uri
      return unless self['/source/youtube/channel/url']
      Ginseng::URI.parse(config['/source/youtube/channel/url'])
    end

    def channel_id
      return self['/source/youtube/channel/id']
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.select {|s| s.is_a?(self)}.each(&block)
    end
  end
end
