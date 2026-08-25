module TomatoShrieker
  class PiefedShriekerTest < TestCase
    def disable?
      return true if Source.all.none? {|s| s.test? && s.piefed?}
      return super
    end

    def test_exec
      Source.all.select(&:test?).select(&:piefed).each do |source|
        source.clear
        assert_nothing_raised {source.exec}
      end
    end

    def test_templates
      Source.all.select(&:test?).select(&:piefed).each do |source|
        assert_kind_of(Hash, source.templates)
        assert_kind_of(Template, source.templates[:default])
      end
    end
  end
end

module TomatoShrieker
  # ⚠ 上の PiefedShriekerTest は dest に piefed を持つテスト用ソースが手元に無いと
  # `disable?` で丸ごと落ちる (#1520)。login の遅延だけは環境に依らず見たいので、
  # webmock で閉じた独立のテストケースにする。
  class PiefedShriekerLoginTest < TestCase
    PARAMS = {
      host: 'piefed.example.com',
      user_id: 'user@example.com',
      password: 'password',
      community_id: 1,
    }.freeze

    def setup
      WebMock.enable!
      WebMock.disable_net_connect!
      @stub = stub_request(:post, %r{/user/login}).to_return(
        status: 200,
        body: '{"jwt":"dummy"}',
        headers: {'Content-Type' => 'application/json'},
      )
    end

    def teardown
      WebMock.allow_net_connect!
      WebMock.disable!
      super
    end

    # #1514: 構築時に無条件で login すると、投稿しないケース（設定の読み込み・
    # source list・テストの初期化）でも認証 API を叩き、429 を踏みやすくなる。
    def test_does_not_login_on_initialize
      PiefedShrieker.new(PARAMS)

      assert_not_requested(@stub)
    end

    def test_logs_in_on_demand
      shrieker = PiefedShrieker.new(PARAMS)
      shrieker.login

      assert_requested(@stub, times: 1)
    end

    # ⚠ 上流の Service#login は `return if @jwt` を持つ。exec のたびに叩き直さない。
    def test_does_not_login_twice
      shrieker = PiefedShrieker.new(PARAMS)
      2.times {shrieker.login}

      assert_requested(@stub, times: 1)
    end
  end
end
