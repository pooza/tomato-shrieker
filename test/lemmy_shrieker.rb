module TomatoShrieker
  class LemmyShriekerTest < TestCase
    def setup
      return unless @source = Source.all.find(&:lemmy?)
      @shrieker = @source.shriekers.find {|v| v.is_a?(LemmyShrieker)}
      @template = Template.new('common')
      @template[:status] = Time.now.to_s
      @template[:source] = @source
    end

    def test_client
      return unless @shrieker
      assert_kind_of(Faye::WebSocket::Client, @shrieker.client)
    end

    def test_login
      return unless @shrieker
      @shrieker.login
    end

    def test_exec
      return unless @shrieker
      assert(@template[:source].lemmy.exec(template: @template))
    end
  end
end
