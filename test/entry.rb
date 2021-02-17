module TomatoShrieker
  class EntryTest < TestCase
    def setup
      @entry = Entry.dataset.all.last
    end

    def test_feed
      assert_kind_of(FeedSource, @entry.feed) if @entry
    end

    def test_template
      assert_kind_of(Template, @entry.template) if @entry
    end

    def test_uri
      assert_kind_of(Ginseng::URI, @entry.uri) if @entry
    end

    def test_enclosure
      assert_kind_of(Ginseng::URI, @entry.enclosure) if @entry&.enclosure
    end

    def test_tags
      (@entry.tags || []).each do |tag|
        assert_kind_of(String, tag)
      end
    end
  end
end
