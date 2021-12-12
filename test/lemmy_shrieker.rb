module TomatoShrieker
  class LemmyShriekerTest < TestCase
    def setup
      @source = Source.all.find {|v| v.id == 'lemmy_test'}
      @shrieker = @source.lemmy
    end

    def test_client
      assert_kind_of(Faye::WebSocket::Client, @shrieker.client)
    end

    def test_exec
      @source.clear
      @source.exec
    end
  end
end
