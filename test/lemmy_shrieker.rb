module TomatoShrieker
  class LemmyShriekerTest < TestCase
    def setup
      @config = Config.instance
      @lemmy = LemmyShrieker.new(@config['/lemmy/services'].first)

      @template = Template.new('common')
      @template[:status] = Time.now.to_s
    end

    def test_exec
      assert(@lemmy.exec(template: @template))
    end
  end
end
