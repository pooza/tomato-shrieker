module TomatoShrieker
  class FeedSourceTest < TestCase
    def test_all
      assert_kind_of(Enumerator, FeedSource.all)
    end

    def test_feedjira
      FeedSource.all do |source|
        assert_kind_of([Feedjira::Parser::Atom, Feedjira::Parser::RSS], source.feedjira)
      end
    end

    def test_unique_title?
      FeedSource.all do |source|
        assert_boolean(source.unique_title?)
      end
    end

    def test_multi_entries?
      FeedSource.all do |source|
        assert_boolean(source.multi_entries?)
      end
    end

    def test_category
      FeedSource.all.select(&:category).each do |source|
        assert_kind_of(String, source.category)
      end
    end

    def test_limit
      FeedSource.all.select(&:multi_entries?).each do |source|
        assert_kind_of(Integer, source.limit)
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

    def test_multi_entries
      FeedSource.all.select(&:multi_entries?).each do |source|
        assert_kind_of(Array, source.multi_entries)
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
        assert(source.entries.count.positive?)
        source.entries.first(5).each do |entry|
          assert_kind_of([Feedjira::Parser::AtomEntry, Feedjira::Parser::AtomYoutubeEntry, Feedjira::Parser::RSSEntry], entry)
        end
      end
    end

    def test_present?
      FeedSource.all do |source|
        assert_boolean(source.present?)
      end
    end

    def test_purge?
      FeedSource.all do |source|
        assert_boolean(source.purge?)
      end
    end

    def test_keep_years
      FeedSource.all.select(&:purge?).each do |source|
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
