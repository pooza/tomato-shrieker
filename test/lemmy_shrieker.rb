module TomatoShrieker
  class LemmyShriekerTest < TestCase
    def disable?
      return true if Source.all.none? {|s| s.test? && s.lemmy?}
      return super
    end

    def test_exec
      Source.all.select(&:test?).select(&:lemmy).each do |source|
        source.clear
        source.exec
      end
    end
  end
end
