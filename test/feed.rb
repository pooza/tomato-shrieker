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
          assert_kind_of(Entry, entry)
        end
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
        feed.hooks do |hook|
          assert_kind_of(Ginseng::URI, hook)
        end
      end
    end

    def test_tags
      Feed.all do |feed|
        assert_kind_of(Array, feed.tags)
        feed.tags do |tag|
          assert_kind_of(String, tag)
        end
      end
    end

    def test_visibility
      Feed.all do |feed|
        assert_kind_of(String, feed.visibility)
      end
    end
  end
end
