module TomatoShrieker
  class MastodonShriekerTest < TestCase
    def disable?
      return true if Source.all.none? {|s| s.test? && s.mastodon?}
      return super
    end

    def test_exec
      Source.all.select(&:test?).select(&:mastodon).each do |source|
        source.clear
        source.exec
      end
    end
  end
end
