module TomatoShrieker
  class LemmyShriekerTest < TestCase
    def setup
      @source = Source.all.find {|v| v.id == 'lemmy_test'}
      @shrieker = @source.lemmy
    end

    def test_client
      assert_kind_of(Faye::WebSocket::Client, @shrieker.client)
    end

    def test_verify_peer?
      assert_boolean(@shrieker.verify_peer?)
    end

    def test_root_cert_file
      assert_path_exists(@shrieker.root_cert_file)
    end

    def test_exec
      @source.clear
      @source.exec
    end
  end
end
