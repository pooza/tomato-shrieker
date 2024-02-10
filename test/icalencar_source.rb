module TomatoShrieker
  class IcalendarSourceTest < TestCase
    def test_all
      assert_kind_of(Enumerator, IcalendarSource.all)
    end

    def test_ical
      IcalendarSource.all.each do |source|
        assert_kind_of(ICalendar, source.feedjira)
      end
    end

    def test_keyword
      IcalendarSource.all.select(&:keyword).each do |source|
        assert_kind_of(Regexp, source.keyword)
      end
    end

    def test_negative_keyword
      IcalendarSource.all.select(&:negative_keyword).each do |source|
        assert_kind_of(Regexp, source.negative_keyword)
      end
    end

    def test_time
      IcalendarSource.all.select(&:touched?).each do |source|
        assert_kind_of(Time, source.time)
      end
    end

    def test_entries
      IcalendarSource.all do |source|
        assert_kind_of(Enumerator, source.entries)
        assert_predicate(source.entries.count, :positive?)
        source.entries.first(5).each do |entry|
          assert_kind_of(Hash, entry)
        end
      end
    end

    def test_present?
      IcalendarSource.all do |source|
        assert_boolean(source.present?)
      end
    end

    def test_uri
      IcalendarSource.all do |source|
        assert_kind_of(Ginseng::URI, source.uri)
      end
    end

    def test_prefix
      IcalendarSource.all do |source|
        assert_kind_of(String, source.prefix)
      end
    end
  end
end
