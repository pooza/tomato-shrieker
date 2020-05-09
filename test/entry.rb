module TomatoToot
  class EntryTest < Test::Unit::TestCase
    def test_feed
      Source.all do |source|
        next unless source.is_a?(FeedSource)
        source.fetch do |entry|
          assert_kind_of(Feed, entry.feed)
        end
      end
    end

    def test_body
      Source.all do |source|
        next unless source.is_a?(FeedSource)
        source.fetch do |entry|
          assert(entry.body.present?)
          assert_kind_of(String, entry.body)
        end
      end
    end

    def test_uri
      Source.all do |source|
        next unless source.is_a?(FeedSource)
        source.fetch do |entry|
          assert_kind_of(Ginseng::URI, entry.uri)
        end
      end
    end

    def test_enclosure
      Source.all do |source|
        next unless source.is_a?(FeedSource)
        source.fetch do |entry|
          next if entry.enclosure.nil?
          assert_kind_of(Ginseng::URI, entry.enclosure)
        end
      end
    end
  end
end
