module TomatoToot
  class FeedTest < Test::Unit::TestCase
    def test_new
      Feed.all do |feed|
        assert_true(feed.is_a?(Feed))
      end
    end

    def test_status
      Feed.all do |feed|
        assert_true(feed.status.is_a?(Hash))
      end
    end

    def test_uri
      Feed.all do |feed|
        assert_true(feed.uri.is_a?(Addressable::URI))
      end
    end

    def test_mastodon
      Feed.all do |feed|
        assert_true(feed.mastodon.is_a?(Mastodon))
      end
    end

    def test_toot_tags
      Feed.all do |feed|
        assert_true(feed.toot_tags.is_a?(Array))
      end
    end
  end
end
