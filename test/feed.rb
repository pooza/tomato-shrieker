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

    def test_to_h
      Feed.all do |feed|
        assert_kind_of(Hash, feed.to_h)
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

    def test_tag
      Feed.all do |feed|
        next unless feed.tag
        assert_kind_of(String, feed.tag)
      end
    end

    def test_prefix
      Feed.all do |feed|
        assert_kind_of(String, feed.prefix)
      end
    end

    def test_mulukhiya?
      Feed.all do |feed|
        assert_boolean(feed.mulukhiya?)
      end
    end

    def test_bot?
      Feed.all do |feed|
        assert_boolean(feed.bot?)
      end
    end

    def test_touched?
      Feed.all do |feed|
        assert_boolean(feed.touched?)
      end
    end

    def test_template
      Feed.all do |feed|
        assert_kind_of(String, feed.template)
      end
    end

    def test_mode
      Feed.all do |feed|
        assert_kind_of(String, feed.mode)
      end
    end

    def test_present?
      Feed.all do |feed|
        assert_boolean(feed.present?)
      end
    end

    def test_hooks
      Feed.all do |feed|
        feed.hooks do |hook|
          assert_kind_of(Slack, hook)
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
