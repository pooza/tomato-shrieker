module TomatoShrieker
  class EntryTest < TestCase
    def setup
      @entries = Entry.dataset.all.select(&:feed)
    end

    def test_feed
      assert_kind_of(FeedSource, @entries.sample.feed)
    end

    def test_template
      if entry = @entries.find(&:template)
        assert_kind_of(Template, entry.template)
      end
    end

    def test_uri
      if entry = @entries.find(&:uri)
        assert_kind_of(Ginseng::URI, entry.uri)
      end
    end

    def test_enclosure
      if entry = @entries.find(&:enclosure)
        assert_kind_of(Ginseng::URI, entry.enclosure)
      end
    end

    def test_tags
      if entry = @entries.find {|v| v.tags.count.positive?}
        entry.tags.each do |tag|
          assert_kind_of(String, tag)
        end
      end
    end
  end
end
