module TomatoToot
  class FeedTest < Test::Unit::TestCase
    def setup
      @config = Config.instance
      @feeds = []
      @config['/entries'].each do |entry|
        next unless entry['source']
        next if entry['webhook']
        @feeds.push(Feed.new(entry))
      end
    end

    def test_new
      @feeds.each do |feed|
        assert_true(feed.is_a?(Feed))
      end
    end

    def test_status
      @feeds.each do |feed|
        assert_true(feed.status.is_a?(Hash))
      end
    end

    def test_uri
      @feeds.each do |feed|
        assert_true(feed.uri.is_a?(Addressable::URI))
      end
    end

    def test_mastodon
      @feeds.each do |feed|
        assert_true(feed.mastodon.is_a?(Mastodon))
      end
    end

    def test_toot_tags
      @feeds.each do |feed|
        assert_true(feed.toot_tags.is_a?(Array))
      end
    end
  end
end
