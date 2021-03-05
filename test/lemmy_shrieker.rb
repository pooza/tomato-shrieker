module TomatoShrieker
  class LemmyShriekerTest < TestCase
    def setup
      @config = Config.instance
      @template = Template.new('common')
      @template[:status] = Time.now.to_s
      @template[:source] = Source.all.find(&:lemmy?)
    end

    def test_exec
      assert(@template[:source].lemmy.exec(template: @template))
    end
  end
end
