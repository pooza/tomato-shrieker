module TomatoShrieker
  class TextSourceTest < TestCase
    def test_command
      TextSource.all do |source|
        assert_kind_of(String, source.text)
      end
    end
  end
end
