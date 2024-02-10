module TomatoShrieker
  class IcalendarSourceTest < TestCase
    def test_all
      assert_kind_of(Enumerator, IcalendarSource.all)
    end

    def test_ical
      IcalendarSource.all.each do |source|
        assert_kind_of(Icalendar::Calendar, source.ical)
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

    def test_entries
      IcalendarSource.all do |source|
        assert_kind_of(Enumerator, source.entries)
        source.entries.first(5).each do |entry|
          assert_kind_of(Hash, entry)
          assert_kind_of(Time, entry[:start_date])
          assert_kind_of(Time, entry[:end_date])
          assert_kind_of([String, NilClass], entry[:title])
          assert_kind_of([String, NilClass], entry[:body])
          assert_kind_of([String, NilClass], entry[:description])
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
