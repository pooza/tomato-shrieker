module TomatoShrieker
  class LemmyShriekerTest < TestCase
    def disable?
      return true if Source.all.none? {|s| s.test? && s.lemmy?}
      return super
    end

    def test_client
      Source.all.select(&:test?).select(&:lemmy).each do |source|
        assert_kind_of(Faye::WebSocket::Client, source.lemmy.client)
      end
    end

    def test_verify_peer?
      Source.all.select(&:test?).select(&:lemmy).each do |source|
        assert_boolean(source.lemmy.verify_peer?)
      end
    end

    def test_root_cert_file
      Source.all.select(&:test?).select(&:lemmy).each do |source|
        assert_path_exist(source.lemmy.root_cert_file)
      end
    end

    def test_exec
      Source.all.select(&:test?).select(&:lemmy).each do |source|
        source.clear
        source.exec
      end
    end
  end
end
