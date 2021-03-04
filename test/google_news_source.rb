module TomatoShrieker
  class GoogleNewsSourceTest < TestCase
    def test_fetch
      GoogleNewsSource.all do |source|
        source.fetch do |entry|
          assert_kind_of(NewsEntry, entry)
        end
      end
    end

    def test_all
      assert_kind_of(Enumerator, GoogleNewsSource.all)
    end
  end
end
