module TomatoShrieker
  class NostrShriekerTest < TestCase
    def disable?
      return true if Source.all.none? {|s| s.test? && s.nostr?}
      return super
    end

    def test_exec
      Source.all.select(&:test?).select(&:nostr?).each do |source|
        source.clear
        source.exec
      end
    end
  end
end
