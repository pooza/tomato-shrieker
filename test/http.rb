module TomatoShrieker
  class HTTPTest < TestCase
    URL = 'https://example.com/feed.rss'.freeze

    # ⚠ TestCase は webmock を require して WebMock::API を include しているだけで、
    # WebMock.enable! を呼んでいない (#1468)。有効化しないと stub_request は何も
    # 傍受せず、実 example.com の 404 を拾って通ってしまう（実際に踏んだ）。
    # ⚠ 全体で有効化すると実サーバーへ出ている既存テストが全部落ちるので、
    # このテストケースの中だけで開閉する。
    def setup
      WebMock.enable!
      WebMock.disable_net_connect!
    end

    def teardown
      WebMock.allow_net_connect!
      WebMock.disable!
      super
    end

    # #1500: YouTube の /feeds/videos.xml はチャンネルが生きていても間欠的に 404 を返す。
    # 恒久的な失敗として即 raise すると、一過性の揺らぎがそのまま run の失敗になる。
    def test_retries_not_found_when_enabled
      stub = stub_request(:get, URL).to_return({status: 404}, {status: 200, body: 'ok'})
      http = HTTP.new
      http.retry_not_found = true

      assert_equal('ok', http.get(URL).body)
      assert_requested(stub, times: 2)
    end

    # ⚠ 既定は再送しない。ginseng-core の「恒久的な失敗を再送しない」方針を巻き戻さない。
    # webhook の POST が返す 404 は宛先設定の誤りで、再送しても結果は変わらない (#1455)。
    def test_does_not_retry_not_found_by_default
      stub = stub_request(:get, URL).to_return({status: 404}, {status: 200, body: 'ok'})

      assert_raise(Ginseng::GatewayError) {HTTP.new.get(URL)}
      assert_requested(stub, times: 1)
    end

    # 404 だけを開ける。401 / 403 まで再送すると、待ち時間とログが retry_limit 倍になる
    def test_retry_not_found_does_not_widen_other_4xx
      stub = stub_request(:get, URL).to_return({status: 403}, {status: 200, body: 'ok'})
      http = HTTP.new
      http.retry_not_found = true

      assert_raise(Ginseng::GatewayError) {http.get(URL)}
      assert_requested(stub, times: 1)
    end

    # 5xx は既定でも再送する（この振る舞いを壊していないこと）
    def test_retries_server_error_by_default
      stub = stub_request(:get, URL).to_return({status: 500}, {status: 200, body: 'ok'})

      assert_equal('ok', HTTP.new.get(URL).body)
      assert_requested(stub, times: 2)
    end

    # 再送しても直らなければ最後は raise する
    def test_gives_up_after_retry_limit
      stub = stub_request(:get, URL).to_return(status: 404)
      http = HTTP.new
      http.retry_not_found = true

      assert_raise(Ginseng::GatewayError) {http.get(URL)}
      assert_requested(stub, times: http.retry_limit)
    end

    # 取得側だけを開ける。FeedSource が opt-in していること
    def test_feed_source_enables_retry_not_found
      source = FeedSource.new({'id' => '__test_http__', 'source' => {'feed' => URL}})

      assert_true(source.instance_variable_get(:@http).retry_not_found)
    end

    # 宛先への POST は開けない。ここが true になったら #1455 の再来
    def test_webhook_shrieker_does_not_retry_not_found
      shrieker = WebhookShrieker.new('https://example.com/hook')

      assert_not_equal(true, shrieker.instance_variable_get(:@http).retry_not_found)
    end
  end
end
