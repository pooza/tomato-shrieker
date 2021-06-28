module TomatoShrieker
  class LemmyShriekerTest < TestCase
    def setup
      source = Source.all.find(&:lemmy?)
      @shrieker = source.lemmy
      @template = Template.new('common')
      @template[:status] = Time.now.to_s
      @template[:source] = source
    end

    def test_client
      assert_kind_of(Faye::WebSocket::Client, @shrieker.client)
    end

    def test_exec
      @template[:source].lemmy.exec(template: @template)
    end
  end
end
