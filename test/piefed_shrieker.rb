module TomatoShrieker
  class PiefedShriekerTest < TestCase
    def disable?
      return true if Source.all.none? {|s| s.test? && s.piefed?}
      return super
    end

    def test_exec
      Source.all.select(&:test?).select(&:piefed).each do |source|
        source.clear
        source.exec
      end
    end
  end
end
