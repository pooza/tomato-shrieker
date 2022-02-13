module TomatoShrieker
  class TweetTimelineSource < FeedSource
    def uri
      uri = Ginseng::URI.parse(config['/tweet/urls/root'])
      uri.path = File.join('/', account, 'rss')
      return uri
    end

    def account
      return self['/source/tweet/account']
    end

    def default_period
      return '10m'
    end

    alias every period

    def ignore_entry?(entry)
      return true if entry.title&.match?(/^(RT by|R to)\s/)
      return super
    end

    def create_record(entry)
      values = entry.to_h
      uri = Ginseng::URI.parse(values['url'])
      uri.host = 'twitter.com'
      uri.fragment = nil
      values['url'] = uri.to_s
      return super(values)
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.select {|s| s.is_a?(TweetTimelineSource)}.each(&block)
    end
  end
end
