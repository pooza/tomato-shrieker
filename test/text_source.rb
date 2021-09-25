module TomatoShrieker
  class TextSourceTest < TestCase
    def test_text
      TextSource.all do |source|
        assert_kind_of(String, source.text)
        assert(source.text.present?)
      end
    end
  end
end
