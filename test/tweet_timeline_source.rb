module TomatoShrieker
  class TweetTimelineSourceTest < TestCase
    def test_all
      assert_kind_of(Enumerator, TweetTimelineSource.all)
    end


    def test_account
      TweetTimelineSource.all do |source|
        assert_kind_of(String, source.account)
        assert(source.account.present?)
      end
    end
  end
end
