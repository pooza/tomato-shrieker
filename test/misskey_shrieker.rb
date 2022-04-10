module TomatoShrieker
  class MisskeyShriekerTest < TestCase
    def test_exec
      Source.all.select(&:test?).select(&:misskey).each do |source|
        source.clear
        source.exec
      end
    end
  end
end
