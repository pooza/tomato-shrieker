module TomatoShrieker
  class PackageTest < TestCase
    # 🔴 例外メッセージに埋まった資格情報が落ちること (#1511)。
    #
    # ⚠ Package.error_message は **source_run_log.error_message の唯一の入口**で、
    # かつ /healthz/source の 503 本文にも使われる。ここを通った文字列は
    # /status.json からそのまま読める。本番の monitor.bind は 0.0.0.0 なので
    # LAN / VPN の誰からでも見える (#1531)。
    WEBHOOK_DIGEST = 'fa9c541e163ff35ac49e12dd5ad71dc4e27876a3a5514f46d074e9b6f190652d'.freeze

    def test_error_message
      assert_nil(Package.error_message(nil))
      assert_equal(
        'Ginseng::GatewayError: Bad response 404',
        Package.error_message(Ginseng::GatewayError.new('Bad response 404')),
      )
    end

    # WebhookShrieker の失敗はこの形になる。digest を知っていれば誰でも投稿できる。
    def test_error_message_masks_webhook_digest
      error = Ginseng::GatewayError.new(
        "Bad response 404 (https://precure.ml/mulukhiya/webhook/#{WEBHOOK_DIGEST})",
      )

      message = Package.error_message(error)

      assert_not_include(message, WEBHOOK_DIGEST)
      assert_include(message, '[FILTERED]')
      assert_include(message, 'Bad response 404', '診断に要る情報は残す')
    end

    # FeedSource#feedjira は URI を丸ごとメッセージへ埋める。認証付きフィードを
    # 足した時点で、そのまま run_log へ保存される。
    def test_error_message_masks_feed_token
      error = Ginseng::GatewayError.new(
        'Invalid feed x (https://example.com/feed.xml?access_token=TOKENVALUE) Bad response 500',
      )

      message = Package.error_message(error)

      assert_not_include(message, 'TOKENVALUE')
      assert_include(message, 'Bad response 500')
    end

    # ⚠ 資格情報を含まない URL は残すこと。消すとどのフィードが壊れたのか判らない。
    def test_error_message_keeps_harmless_url
      error = Ginseng::GatewayError.new(
        'Invalid feed vjump-youtube (https://www.youtube.com/feeds/videos.xml?channel_id=UCTwO5UAGiB8AdFrsxhNKaRQ) Bad response 404',
      )

      message = Package.error_message(error)

      assert_include(message, 'UCTwO5UAGiB8AdFrsxhNKaRQ')
      assert_include(message, 'vjump-youtube')
    end

    # ⚠ 不正なバイト列でもマスクごと素通りしないこと (#518 / #1469 の族)。
    # to_utf8 の後にマスクを通しているかを見る。
    def test_error_message_masks_broken_bytes
      error = Ginseng::GatewayError.new(
        "\xE3\x81 (https://precure.ml/mulukhiya/webhook/#{WEBHOOK_DIGEST})",
      )

      message = Package.error_message(error)

      assert_not_include(message, WEBHOOK_DIGEST)
      assert_true(message.valid_encoding?)
    end
  end
end
