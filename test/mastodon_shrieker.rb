module TomatoShrieker
  class MastodonShriekerTest < TestCase
    def disable?
      return true if Source.all.none? {|s| s.test? && s.mastodon?}
      return super
    end

    def test_exec
      Source.all.select(&:test?).select(&:mastodon).each do |source|
        source.clear
        assert_nothing_raised { source.exec }
      end
    end

    def test_templates
      Source.all.select(&:test?).select(&:mastodon).each do |source|
        assert_kind_of(Hash, source.templates)
        assert_kind_of(Template, source.templates[:default])
      end
    end
  end
end
