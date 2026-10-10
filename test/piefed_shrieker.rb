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

    # #1631: `include Package` が無いと `http_class` が gem 既定の `Ginseng::HTTP` に
    # 倒れ、tomato の `/http/retry/limit`・User-Agent・マスクが PieFed 宛にだけ効かない。
    def test_uses_package_http
      http = PiefedShrieker.new(PARAMS).http

      assert_instance_of(HTTP, http)
      assert_equal(config['/http/retry/limit'], http.retry_limit)
    end

    # #1620: 資格情報（JWT）を運ぶ要求がリダイレクト先へ持ち越されないこと。
    def test_does_not_follow_redirect
      stub_request(:post, %r{/api/[^/]+/post}).to_return(
        status: 307,
        headers: {'Location' => 'https://evil.example.com/post'},
      )
      evil = stub_request(:post, 'https://evil.example.com/post')
      shrieker = PiefedShrieker.new(PARAMS)
      shrieker.login

      assert_raise(Ginseng::GatewayError) do
        shrieker.http.post("/api/#{shrieker.api_version}/post", {
          body: {title: 'x'},
          headers: {'Authorization' => 'Bearer dummy'},
        })
      end
      assert_not_requested(evil)
    end

    # 🔴 **#1484: タグは本文にだけ付き、タイトルには付かない。他の宛先に左右されない。**
    # ⚠ 以前は `[:tag]` を立てずに描画していたので、単独なら付かず、Mastodon / Misskey と
    # 併用なら付き、Line と併用なら落ちていた。
    def test_post_data_tags_body_only
      [nil, true, false].each do |leaked|
        template = tagged_source.create_template(:default, 'フィクスチャの本文')
        template[:tag] = leaked
        data = PiefedShrieker.new(PARAMS).send(:post_data, template)

        assert_include(data[:body], '#fixture_tag', "body（前の宛先のフラグ: #{leaked.inspect}）")
        assert_not_include(data[:title], '#fixture_tag', "title（前の宛先のフラグ: #{leaked.inspect}）")
        assert_include(data[:title], 'フィクスチャの本文')
        assert_equal(1, data[:community_id])
      end
    end

    # ⚠ タグ付きの描画は 1 回だけ（#1664 の Codex P2）。URL の控えも同じ描画から取る。
    def test_post_data_renders_tagged_body_once
      template = tagged_source.create_template(:default, '本文 https://example.com/a')
      tagged = 0
      original = template.method(:to_s)
      template.define_singleton_method(:to_s) do
        tagged += 1 if self[:tag]
        original.call
      end
      data = PiefedShrieker.new(PARAMS).send(:post_data, template)

      assert_equal(1, tagged)
      assert_equal('https://example.com/a', data[:url])
      assert_not_include(data[:body], 'https://example.com/a')
    end

    def tagged_source
      return TextSource.new(
        'id' => '__test_piefed_tags__',
        'source' => {'text' => 'フィクスチャの本文'},
        'schedule' => {'every' => '1d'},
        'dest' => {'tags' => ['fixture_tag'], 'piefed' => PARAMS.transform_keys(&:to_s)},
      )
    end
  end
end
