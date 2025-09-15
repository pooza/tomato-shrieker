module TomatoShrieker
  class FeedSourceTest < TestCase
    def test_all
      assert_kind_of(Enumerator, FeedSource.all)
    end

    def test_feedjira
      FeedSource.all do |source|
        classes = [
          Feedjira::Parser::Atom,
          Feedjira::Parser::RSS,
          Feedjira::Parser::AtomYoutube,
          Feedjira::Parser::ITunesRSS,
        ]

        assert_kind_of(classes, source.feedjira)
      end
    end

    def test_enclosure?
      FeedSource.all do |source|
        assert_boolean(source.enclosure?)
      end
    end

    def test_category
      FeedSource.all.select(&:category).each do |source|
        assert_kind_of(String, source.category)
      end
    end

    def test_keyword
      FeedSource.all.select(&:keyword).each do |source|
        assert_kind_of(Regexp, source.keyword)
      end
    end

    def test_negative_keyword
      FeedSource.all.select(&:negative_keyword).each do |source|
        assert_kind_of(Regexp, source.negative_keyword)
      end
    end

    def test_time
      FeedSource.all.select(&:touched?).each do |source|
        assert_kind_of(Time, source.time)
      end
    end

    def test_touched?
      FeedSource.all do |source|
        assert_boolean(source.touched?)
      end
    end

    def test_entries
      FeedSource.all do |source|
        assert_kind_of(Enumerator, source.entries)
        assert_predicate(source.entries.count, :positive?)
        source.entries.first(5).each do |entry|
          classes = [
            Feedjira::Parser::AtomEntry,
            Feedjira::Parser::RSSEntry,
            Feedjira::Parser::AtomYoutubeEntry,
            Feedjira::Parser::ITunesRSSItem,
          ]

          assert_kind_of(classes, entry)
        end
      end
    end

    def test_present?
      FeedSource.all do |source|
        assert_boolean(source.present?)
      end
    end

    def test_purgeable?
      FeedSource.all do |source|
        assert_boolean(source.purgeable?)
      end
    end

    def test_keep_years
      FeedSource.all.select(&:purgeable?).each do |source|
        assert_kind_of(Integer, source.keep_years)
      end
    end

    def test_uri
      FeedSource.all do |source|
        assert_kind_of(Ginseng::URI, source.uri)
      end
    end

    def test_prefix
      FeedSource.all do |source|
        assert_kind_of(String, source.prefix)
      end
    end
  end
end
