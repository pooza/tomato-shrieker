module TomatoShrieker
  class TweetTimelineSourceTest < TestCase
    def test_time
      TweetTimelineSource.all.select(&:time).each do |source|
        assert_kind_of(Time, source.time)
      end
    end

    def test_touched?
      TweetTimelineSource.all do |source|
        assert_boolean(source.touched?)
      end
    end

    def test_present?
      TweetTimelineSource.all do |source|
        assert_boolean(source.present?)
      end
    end

    def test_uri
      TweetTimelineSource.all do |source|
        assert_kind_of(Ginseng::URI, source.uri)
      end
    end

    def test_feedjira
      TweetTimelineSource.all do |source|
        assert(source.feedjira.present?)
        assert_kind_of(Array, source.feedjira.entries)
        assert(source.feedjira.entries.count.positive?)
      end
    end

    def test_unique_title?
      TweetTimelineSource.all do |source|
        assert_boolean(source.unique_title?)
      end
    end

    def test_keyword
      TweetTimelineSource.all.select(&:keyword).each do |source|
        assert_kind_of(Regexp, source.keyword)
      end
    end

    def test_negative_keyword
      TweetTimelineSource.all.select(&:negative_keyword).each do |source|
        assert_kind_of(Regexp, source.negative_keyword)
      end
    end

    def test_multi_entries_template
      TweetTimelineSource.all.select(&:multi_entries?).each do |source|
        assert_kind_of(Template, source.multi_entries_template)
      end
    end

    def test_purge
      TweetTimelineSource.all do |source|
        next unless time = source.purge(dryrun: true)
        assert_kind_of(Time, time)
      end
    end

    def test_all
      assert_kind_of(Enumerator, TweetTimelineSource.all)
    end
  end
end
