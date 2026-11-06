module TomatoShrieker
  class HTTPTest < TestCase
    URL = 'https://example.com/feed.rss'.freeze

    # ⚠ 有効化しないと stub_request は何も傍受せず、実 example.com の 404 を拾って
    # 通ってしまう（#1468 で実際に踏んだ）。いまは TestCase が毎テスト有効化しているが、
    # このケースは傍受が前提なので、ここでも明示しておく。
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

    # #1688: 運用者の設定した取得元は、LAN 内のホストでも取れる（初段は検証しない）
    def test_get_configured_allows_internal_origin
      url = 'http://scylla.b-shock.local:3000/feed'
      stub_request(:get, url).to_return(status: 200, body: 'ok')

      assert_equal('ok', HTTP.new.get_configured(url).body)
    end

    # #1688: 同じホストへのリダイレクトは初段と同じ扱いで追う
    def test_get_configured_follows_same_host_redirect
      stub_request(:get, URL).to_return(status: 301, headers: {'Location' => 'https://example.com/moved.rss'})
      stub_request(:get, 'https://example.com/moved.rss').to_return(status: 200, body: 'ok')

      assert_equal('ok', HTTP.new.get_configured(URL).body)
    end

    # #1688: 別のホストへのリダイレクトで内部を指されたら、そこへは GET しない
    def test_get_configured_rejects_redirect_to_internal_host
      stub_request(:get, URL).to_return(status: 302, headers: {'Location' => 'http://127.0.0.1/admin'})
      internal = stub_request(:get, 'http://127.0.0.1/admin').to_return(status: 200, body: 'secret')

      assert_raise(Ginseng::GatewayError) {HTTP.new.get_configured(URL)}
      assert_not_requested(internal)
    end

    # #1688: 初段以外のホストは PublicHost の判定に委ねる（大文字小文字は区別しない）
    def test_configured_host_validator
      public_host = ->(host) {host == 'public.example' ? '203.0.113.1' : nil}
      validator = HTTP.configured_host_validator('Example.COM', public_host:)

      assert_true(validator.call('example.com'))
      assert_equal('203.0.113.1', validator.call('public.example'))
      assert_nil(validator.call('internal.example'))
    end

    # #1688: FeedSource / IcalendarSource の取得がこの経路を通ること
    def test_sources_reject_redirect_to_internal_host
      stub_request(:get, %r{\Ahttps://example\.com/feed\.rss}).to_return(status: 302, headers: {'Location' => 'http://127.0.0.1/admin'})
      internal = stub_request(:get, 'http://127.0.0.1/admin').to_return(status: 200, body: 'secret')
      feed = FeedSource.new({'id' => '__test_http__', 'source' => {'feed' => URL}})
      ical = IcalendarSource.new({'id' => '__test_http__', 'source' => {'calendar' => URL}})

      assert_raise(Ginseng::GatewayError) {feed.feedjira}
      assert_raise(Ginseng::GatewayError) {ical.ical}
      assert_not_requested(internal)
    end
  end
end
