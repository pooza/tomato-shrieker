module TomatoToot
  class FeedTest < Test::Unit::TestCase
    def test_all
      Feed.all do |feed|
        assert(feed.is_a?(Feed))
      end
    end

    def test_fetch
      Feed.all do |feed|
        feed.fetch do |entry|
          assert(entry.is_a?(FeedEntry))
        end
      end
    end

    def test_fetch_all
      Feed.all do |feed|
        feed.fetch_all do |entry|
          assert(entry.is_a?(FeedEntry))
        end
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
        next unless feed.mastodon
        assert(feed.mastodon.is_a?(Mastodon))
      end
    end

    def test_hooks
      Feed.all do |feed|
        assert(feed.hooks.is_a?(Array))
      end
    end

    def test_toot_tags
      Feed.all do |feed|
        assert(feed.toot_tags.is_a?(Array))
      end
    end

    def test_visibility
      Feed.all do |feed|
        assert(feed.visibility.is_a?(String))
      end
    end

    def test_timestamp
      Feed.all do |feed|
        assert(feed.timestamp.is_a?(Time))
      end
    end
  end
end
