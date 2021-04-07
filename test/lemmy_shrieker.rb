module TomatoShrieker
  class LemmyShriekerTest < TestCase
    def setup
      @source = Source.all.find(&:lemmy?)
      return unless @source
      @shrieker = @source.shriekers.find {|v| v.is_a?(LemmyShrieker)}
      @config = Config.instance
      @template = Template.new('common')
      @template[:status] = Time.now.to_s
      @template[:source] = @source
    end

    def test_client
      return unless @source
      assert_kind_of(Faye::WebSocket::Client, @shrieker.client)
      @shrieker.login
    end

    def test_exec
      return unless @source
      assert(@template[:source].lemmy.exec(template: @template))
    end
  end
end
