module TomatoShrieker
  class GoogleNewsSourceTest < TestCase
    def test_time
      GoogleNewsSource.all.select(&:time).each do |source|
        assert_kind_of(Time, source.time)
      end
    end

    def test_touched?
      GoogleNewsSource.all do |source|
        assert_boolean(source.touched?)
      end
    end

    def test_present?
      GoogleNewsSource.all do |source|
        assert_boolean(source.present?)
      end
    end

    def test_uri
      GoogleNewsSource.all do |source|
        assert_kind_of(Ginseng::URI, source.uri)
      end
    end

    def test_feedjira
      GoogleNewsSource.all do |source|
        assert(source.feedjira.present?)
        assert_kind_of(Array, source.feedjira.entries)
        assert(source.feedjira.entries.count.positive?)
      end
    end

    def test_unique_title?
      GoogleNewsSource.all do |source|
        assert_boolean(source.unique_title?)
      end
    end

    def test_expire
      GoogleNewsSource.all do |source|
        assert_kind_of(Integer, source.expire)
      end
    end

    def test_keyword
      GoogleNewsSource.all.select(&:keyword).each do |source|
        assert_kind_of(Regexp, source.keyword)
      end
    end

    def test_negative_keyword
      GoogleNewsSource.all.select(&:negative_keyword).each do |source|
        assert_kind_of(Regexp, source.negative_keyword)
      end
    end

    def test_multi_entries_template
      GoogleNewsSource.all.select(&:multi_entries?).each do |source|
        assert_kind_of(Template, source.multi_entries_template)
      end
    end

    def test_purge
      GoogleNewsSource.all do |source|
        next unless time = source.purge(dryrun: true)
        assert_kind_of(Time, time)
      end
    end

    def test_all
      assert_kind_of(Enumerator, GoogleNewsSource.all)
    end
  end
end
