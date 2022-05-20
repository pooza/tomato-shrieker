module TomatoShrieker
  class MisskeyShriekerTest < TestCase
    def disable?
      return true if Source.all.none? {|s| s.test? && s.misskey?}
      return super
    end

    def test_exec
      Source.all.select(&:test?).select(&:misskey).each do |source|
        source.clear
        source.exec
      end
    end
  end
end
