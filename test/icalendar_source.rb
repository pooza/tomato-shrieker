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

    def test_sanitize_mode
      IcalendarSource.all.each do |source|
        assert_includes([:fedi, :html], source.sanitize_mode)
      end
    end

    def test_fedi_sanitize?
      IcalendarSource.all.each do |source|
        assert_kind_of([TrueClass, FalseClass], source.fedi_sanitize?)
      end
    end

    def test_google?
      IcalendarSource.all.each do |source|
        assert_kind_of([TrueClass, FalseClass], source.google?)
      end
    end

    def test_sanitize
      source = %{<a href="https://shonenjumpplus.com/episode/17106371859967525169">https://shonenjumpplus.com/episode/17106371859967525169</a><br>感想には是非、以下のタグをどうぞ！<br>#勇者アバン_42話<br>#勇者アバン_11巻 (11巻2話目にあたります)<br><br>#delmulin #更新}
      sanitized = %{https://shonenjumpplus.com/episode/17106371859967525169\n感想には是非、以下のタグをどうぞ！\n#勇者アバン_42話\n#勇者アバン_11巻 (11巻2話目にあたります)\n\n#delmulin #更新}

      assert_equal(sanitized, source.sanitize)
    end

    def test_fix_google_calendar_entry
      source = IcalendarSource.new({})
      entry = source.fix_google_calendar_entry(
        body: "無理はせず、スコアのある、蓄積開始後ほこらに備えましょう #頑張りましたで称号\n\n#DQW期限\n\nGoogle Meet に参加: https://meet.google.com/aaa-bbbc-ccc\n\nMeet の詳細: https://support.google.com/a/users/ans",
        location: '渋谷WOMBLOUNGE, 日本、〒150-0044 東京都渋谷区円山町２−１６',
      )

      assert_equal("無理はせず、スコアのある、蓄積開始後ほこらに備えましょう #頑張りましたで称号\n\n#DQW期限", entry[:body])
      assert_equal('渋谷WOMBLOUNGE', entry[:location])
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
        assert_kind_of([String, NilClass], source.prefix)
      end
    end
  end
end
