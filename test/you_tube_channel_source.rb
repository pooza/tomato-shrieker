module TomatoShrieker
  class YouTubeChannelSourceTest < TestCase
    def test_all
      assert_kind_of(Enumerator, YouTubeChannelSource.all)
    end

    def test_channel_id
      YouTubeChannelSource.all do |source|
        assert_kind_of(String, source.channel_id)
        assert_predicate(source.channel_id, :present?)
      end
    end

    def test_channel_uri
      YouTubeChannelSource.all do |source|
        assert_kind_of(Ginseng::URI, source.channel_uri)
      end
    end

    def test_feed_uri
      YouTubeChannelSource.all do |source|
        assert_kind_of(Ginseng::URI, source.feed_uri)
      end
    end
  end
end
