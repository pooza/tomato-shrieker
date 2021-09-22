module TomatoShrieker
  class TweetTimelineSource < FeedSource
    def uri
      uri = Ginseng::URI.parse(config['/tweet/urls/root'])
      uri.path = File.join('/', self['/source/tweet/account'], 'rss')
      return uri
    end

    def fetch
      return enum_for(__method__) unless block_given?
      feedjira.entries.sort_by {|entry| entry.published.to_f}.each do |entry|
        next if keyword && !hot_entry?(entry)
        next if negative_keyword && negative_entry?(entry)
        values = entry.clone
        uri = Ginseng::URI.parse(values['url'])
        uri.host = 'twitter.com'
        uri.fragment = nil
        entry['url'] = uri.to_s
        next unless record = Entry.create(values, self)
        yield record
      rescue => e
        logger.error(error: e)
      end
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.select {|s| s.is_a?(TweetTimelineSource)}.each(&block)
    end
  end
end
