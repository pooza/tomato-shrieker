module TomatoShrieker
  class TweetTimelineSource < FeedSource
    def uri
      uri = Ginseng::URI.parse(config['/tweet/urls/root'])
      uri.path = File.join('/', self['/source/tweet/account'], 'rss')
      return uri
    end

    def create_record(entry)
      values = entry.clone
      uri = Ginseng::URI.parse(values['url'])
      uri.host = 'twitter.com'
      uri.fragment = nil
      entry['url'] = uri.to_s
      return super(entry)
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.select {|s| s.is_a?(TweetTimelineSource)}.each(&block)
    end
  end
end
