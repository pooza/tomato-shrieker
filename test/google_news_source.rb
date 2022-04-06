module TomatoShrieker
  class GoogleNewsSourceTest < TestCase
    def test_all
      assert_kind_of(Enumerator, GoogleNewsSource.all)
    end

    def test_phrase
      GoogleNewsSource.all do |source|
        assert_kind_of(String, source.phrase)
        assert_predicate(source.phrase, :present?)
      end
    end
  end
end
