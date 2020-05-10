module TomatoToot
  class EntryTest < Test::Unit::TestCase
    def setup
      @entry = Entry.dataset.all.last
    end

    def test_feed
      assert_kind_of(FeedSource, @entry.feed)
    end

    def test_body
      assert(@entry.body.present?)
      assert_kind_of(String, @entry.body)
    end

    def test_uri
      assert_kind_of(Ginseng::URI, @entry.uri)
    end

    def test_enclosure
      assert_kind_of(Ginseng::URI, @entry.enclosure) if @entry.enclosure
    end
  end
end
