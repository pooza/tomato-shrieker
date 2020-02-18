module TomatoToot
  class FeedTest < Test::Unit::TestCase
    def test_all
      Feed.all do |feed|
        assert_kind_of(Feed, feed)
      end
    end

    def test_fetch
      Feed.all do |feed|
        feed.fetch do |entry|
          assert_kind_of(FeedEntry, entry)
        end
      end
    end

    def test_fetch_all
      Feed.all do |feed|
        feed.fetch_all do |entry|
          assert_kind_of(FeedEntry, entry)
        end
      end
    end

    def test_status
      Feed.all do |feed|
        assert_kind_of(Hash, feed.status)
      end
    end

    def test_uri
      Feed.all do |feed|
        assert_kind_of(Ginseng::URI, feed.uri)
      end
    end

    def test_mastodon
      Feed.all do |feed|
        next unless feed.mastodon
        assert_kind_of(Mastodon, feed.mastodon)
      end
    end

    def test_hooks
      Feed.all do |feed|
        assert_kind_of(Array, feed.hooks)
      end
    end

    def test_toot_tags
      Feed.all do |feed|
        assert_kind_of(Array, feed.toot_tags)
      end
    end

    def test_visibility
      Feed.all do |feed|
        assert_kind_of(String, feed.visibility)
      end
    end

    def test_timestamp
      Feed.all do |feed|
        assert_kind_of(Time, feed.timestamp)
      end
    end
  end
end
