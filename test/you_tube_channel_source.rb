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
  end
end
