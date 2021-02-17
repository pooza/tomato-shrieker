module TomatoShrieker
  class LineShriekerTest < TestCase
    def setup
      @config = Config.instance
      channel = @config['/line/channels']&.first
      @shrieker = LineShrieker.new(channel['user_id'], channel['token']) if channel

      @template = Template.new('common')
      @template[:status] = Time.now.to_s
    end

    def test_exec
      return unless @shrieker
      assert_equal(@shrieker.exec(template: @template).code, 200)
    end
  end
end
