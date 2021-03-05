module TomatoShrieker
  class EntryTest < TestCase
    def setup
      @entries = Entry.dataset.all.select(&:feed)
    end

    def test_feed
      assert_kind_of(FeedSource, @entries.sample.feed)
    end

    def test_template
      return unless entry = @entries.find(&:template)
      assert_kind_of(Template, entry.template)
    end

    def test_uri
      return unless entry = @entries.find(&:uri)
      assert_kind_of(Ginseng::URI, entry.uri)
    end

    def test_enclosure
      return unless entry = @entries.find(&:enclosure)
      assert_kind_of(Ginseng::URI, entry.enclosure)
    end

    def test_tags
      return unless entry = @entries.find {|v| v.tags.count.positive?}
      entry.tags.each do |tag|
        assert_kind_of(String, tag)
      end
    end
  end
end
