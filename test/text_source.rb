module TomatoShrieker
  class TextSourceTest < TestCase
    def test_template
      TextSource.all do |source|
        assert_kind_of(Template, source.template)
      end
    end
  end
end
