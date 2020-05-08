module TomatoToot
  class EntryTest < Test::Unit::TestCase
    def test_feed
      Feed.all do |feed|
        next if feed.command?
        feed.fetch do |entry|
          assert_kind_of(Feed, entry.feed)
        end
      end
    end

    def test_body
      Feed.all do |feed|
        next if feed.command?
        feed.fetch do |entry|
          assert(entry.body.present?)
          assert_kind_of(String, entry.body)
        end
      end
    end

    def test_uri
      Feed.all do |feed|
        next if feed.command?
        feed.fetch do |entry|
          assert_kind_of(Ginseng::URI, entry.uri)
        end
      end
    end

    def test_enclosure
      Feed.all do |feed|
        next if feed.command?
        feed.fetch do |entry|
          next unless entry.enclosure
          assert_kind_of(Ginseng::URI, entry.enclosure)
        end
      end
    end
  end
end
