module TomatoShrieker
  class FeedSourceTest < TestCase
    def test_time
      FeedSource.all.select(&:time).each do |source|
        assert_kind_of(Time, source.time)
      end
    end

    def test_touched?
      FeedSource.all do |source|
        assert_boolean(source.touched?)
      end
    end

    def test_present?
      FeedSource.all do |source|
        assert_boolean(source.present?)
      end
    end

    def test_uri
      FeedSource.all do |source|
        assert_kind_of(Ginseng::URI, source.uri)
      end
    end

    def test_feedjira
      FeedSource.all do |source|
        assert(source.feedjira.present?)
      end
    end

    def test_unique_title?
      FeedSource.all do |source|
        assert_boolean(source.unique_title?)
      end
    end

    def test_expire
      FeedSource.all do |source|
        assert_kind_of(Integer, source.expire)
      end
    end

    def test_keyword
      FeedSource.all.select(&:keyword).each do |source|
        assert_kind_of(Regexp, source.keyword)
      end
    end

    def test_multi_entries_template
      FeedSource.all do |source|
        assert_kind_of([Template, NilClass], source.multi_entries_template)
      end
    end

    def test_purge
      FeedSource.all do |source|
        next unless time = source.purge(dryrun: true)
        assert_kind_of(Time, time)
      end
    end

    def test_all
      assert_kind_of(Enumerator, FeedSource.all)
    end
  end
end
