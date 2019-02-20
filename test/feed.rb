module TomatoToot
  class FeedTest < Test::Unit::TestCase
    def test_new
      Feed.all do |feed|
        assert(feed.is_a?(Feed))
      end
    end

    def test_status
      Feed.all do |feed|
        assert(feed.status.is_a?(Hash))
      end
    end

    def test_uri
      Feed.all do |feed|
        assert(feed.uri.is_a?(Addressable::URI))
      end
    end

    def test_mastodon
      Feed.all do |feed|
        assert(feed.mastodon.is_a?(Mastodon))
      end
    end

    def test_toot_tags
      Feed.all do |feed|
        assert(feed.toot_tags.is_a?(Array))
      end
    end
  end
end
