module TomatoShrieker
  class LemmyShriekerTest < TestCase
    def setup
      @config = Config.instance
      service = @config['/lemmy/services']&.first
      @lemmy = LemmyShrieker.new(service) if service

      @template = Template.new('common')
      @template[:status] = Time.now.to_s
    end

    def test_exec
      return unless @lemmy
      assert(@lemmy.exec(template: @template))
    end
  end
end
