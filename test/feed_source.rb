module TomatoShrieker
  class FeedSourceTest < Test::Unit::TestCase
    def test_time
      Source.all do |source|
        next unless source.is_a?(FeedSource)
        next if source.time.nil?
        assert_kind_of(Time, source.time)
      end
    end

    def test_touched?
      Source.all do |source|
        next unless source.is_a?(FeedSource)
        assert_boolean(source.touched?)
      end
    end

    def test_present?
      Source.all do |source|
        next unless source.is_a?(FeedSource)
        assert_boolean(source.present?)
      end
    end

    def test_uri
      Source.all do |source|
        next unless source.is_a?(FeedSource)
        assert_kind_of(Ginseng::URI, source.uri)
      end
    end

    def test_feedjira
      Source.all do |source|
        next unless source.is_a?(FeedSource)
        assert(source.feedjira.present?)
      end
    end

    def test_unique_title?
      Source.all do |source|
        next unless source.is_a?(FeedSource)
        assert_boolean(source.unique_title?)
      end
    end
  end
end
