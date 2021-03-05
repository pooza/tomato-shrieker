module TomatoShrieker
  class EntryTest < TestCase
    def setup
      @entries = Entry.dataset.all.select(&:feed)
    end

    def test_feed
      assert_kind_of(FeedSource, @entries.sample.feed)
    end

    def test_template
      assert_kind_of(Template, @entries.find(&:template).template)
    end

    def test_uri
      assert_kind_of(Ginseng::URI, @entries.find(&:uri).uri)
    end

    def test_enclosure
      assert_kind_of(Ginseng::URI, @entries.find(&:enclosure).enclosure)
    end

    def test_tags
      @entries.find {|v| v.tags.count.positive?}.tags.each do |tag|
        assert_kind_of(String, tag)
      end
    end
  end
end
