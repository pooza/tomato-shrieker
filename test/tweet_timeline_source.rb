module TomatoShrieker
  class TweetTimelineSourceTest < TestCase
    def test_all
      assert_kind_of(Enumerator, TweetTimelineSource.all)
    end

    def test_account
      TweetTimelineSource.all do |source|
        assert_kind_of(String, source.account)
        assert_predicate(source.account, :present?)
      end
    end

    def test_uris
      TweetTimelineSource.all do |source|
        source.uris do |uri|
          assert_kind_of(Ginseng::URI, uri)
        end
      end
    end

    def test_feedjira
      TweetTimelineSource.all do |source|
        assert_kind_of([Feedjira::Parser::RSS, Feedjira::Parser::Atom], source.feedjira)
      end
    end
  end
end
