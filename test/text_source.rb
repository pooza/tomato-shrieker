module TomatoShrieker
  class TextSourceTest < TestCase
    def test_command
      Source.all do |source|
        next unless source.is_a?(TextSource)
        assert_kind_of(String, source.text)
      end
    end
  end
end
