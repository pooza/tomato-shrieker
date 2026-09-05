module TomatoShrieker
  # Sentry へ送るペイロードから資格情報が落ちていること (#1467)。
  #
  # ⚠⚠ **「マスク処理を呼んでいる」ではなく「出力に含まれていない」を見る。**
  # 呼んでいるかどうかは、対象の列がズレていれば通ってしまう。
  class SentryScrubberTest < TestCase
    # モロヘイヤの webhook は POST /mulukhiya/webhook/{digest} で、**パスその
    # ものが資格情報**。digest を知っていれば誰でもそのアカウントで投稿できる。
    WEBHOOK_DIGEST = 'fa9c541e163ff35ac49e12dd5ad71dc4e27876a3a5514f46d074e9b6f190652d'.freeze
    WEBHOOK_URL = "https://precure.ml/mulukhiya/webhook/#{WEBHOOK_DIGEST}".freeze
    FEED_TOKEN = 'SUPERSECRETTOKEN'.freeze
    FEED_URL = "https://example.com/feed.xml?access_token=#{FEED_TOKEN}".freeze
    # ⚠ 既定にも tomato の設定にも無いキー。`Ginseng::Masking::MASK_FIELDS` の
    # どれかを使うと、reload しなくても最初から落ちてしまい判定にならない。
    PROBE_FIELD = 'shrieker_reload_probe'.freeze
    PROBE_VALUE = 'PROBEPLAINTEXT'.freeze

    def setup
      @scrubber = SentryScrubber.new
    end

    def test_new
      assert_kind_of(SentryScrubber, @scrubber)
    end

    # 🔴 tomato でいちばん漏れる経路。WebhookShrieker の失敗は
    # Ginseng::GatewayError になり、メッセージに URI が丸ごと載る。
    def test_scrub_exception_message
      event = error_event(Ginseng::GatewayError.new("Bad response 404 (#{WEBHOOK_URL})"))

      scrubbed = @scrubber.scrub(event)

      assert_not_nil(scrubbed, 'イベントを落としてはいけない')
      assert_not_include(payload(scrubbed), WEBHOOK_DIGEST)
      assert_include(payload(scrubbed), '[FILTERED]')
    end

    # FeedSource#feedjira は URI を丸ごとメッセージへ埋める。認証付きフィードを
    # 足した時点で、そのまま Sentry へ出る。
    def test_scrub_exception_message_query_credentials
      event = error_event(Ginseng::GatewayError.new("Invalid feed x (#{FEED_URL})"))

      assert_not_include(payload(@scrubber.scrub(event)), FEED_TOKEN)
    end

    # extra / tags は自分で積む場所なので、mask_fields のキーごと落ちること。
    def test_scrub_extra_and_tags
      event = error_event(StandardError.new('boom'))
      event.extra = {password: 'PLAINTEXT', url: WEBHOOK_URL, source: 'shooby'}
      event.tags = {secret: 'PLAINTEXT'}

      scrubbed = payload(@scrubber.scrub(event))

      assert_not_include(scrubbed, 'PLAINTEXT')
      assert_not_include(scrubbed, WEBHOOK_DIGEST)
      assert_include(scrubbed, 'shooby', '無関係な値は残す')
    end

    # ⚠ 資格情報を含まない情報まで消してはいけない。消すと調査に使えなくなる。
    def test_scrub_keeps_diagnostics
      event = error_event(Ginseng::GatewayError.new('Invalid feed vjump-youtube (https://www.youtube.com/feeds/videos.xml?channel_id=UCTwO5UAGiB8AdFrsxhNKaRQ)'))

      scrubbed = payload(@scrubber.scrub(event))

      assert_include(scrubbed, 'vjump-youtube')
      assert_include(scrubbed, 'UCTwO5UAGiB8AdFrsxhNKaRQ')
    end

    # 🔴 **稼働中の `Config#reload` が、掴んだままの logger にも効くこと (#1538)。**
    #
    # `SentryScrubber` は初期化時に logger を 1 個掴んで `before_send` の
    # クロージャへ閉じ込める。⚠ これは意図的で、**設定が読めないときは Sentry ごと
    # 立ち上がらない（fail closed）**という性質を作っている（#1467）。
    #
    # 🔴 `Ginseng::Masking` がマスク一覧を単純な `||=` で memo 化していた頃は、
    # **マスク対象を足して reload しても、この scrubber だけ古い一覧のまま**
    # 送り続けた。⚠ ログには効いてスタックトレースには効かない、という非対称な
    # 形になる（`Package.error_message` は毎回 `Logger.new` するため）。
    # 上流 pooza/ginseng-core#592 で memo の鍵を「合成後」ではなく
    # **設定そのもの**にして解消した。#1459 の reload が入ったのでここで固定する。
    def test_scrub_follows_config_reload
      assert_include(scrubbed_probe, PROBE_VALUE, '前提: まだマスク対象ではない')

      with_mask_field(PROBE_FIELD) do
        assert_not_include(scrubbed_probe, PROBE_VALUE, 'reload が掴んだままの logger に効いていない')
      end
    end

    # 🔴 **fail closed。** マスクを通せなかったイベントは送らない。素通しで送ると
    # 伏せるはずだった値がそのまま外部サービスへ出る。
    def test_scrub_drops_event_when_mask_fails
      event = error_event(StandardError.new('boom'))
      event.define_singleton_method(:extra) {raise 'boom'}

      assert_nil(@scrubber.scrub(event))
    end

    # 🔴 **落としたことをログに残すこと。** `warn` は本番で `/dev/null`
    # （scheduler_daemon が stderr を潰す）なので、そこへ出すと「Sentry へ何も
    # 届かないのに誰も気づけない」になる。
    def test_scrub_logs_when_event_is_dropped
      event = error_event(StandardError.new('boom'))
      event.define_singleton_method(:extra) {raise 'boom'}
      logged = []
      @scrubber.instance_variable_get(:@logger).define_singleton_method(:error) do |arg|
        logged.push(arg)
      end

      @scrubber.scrub(event)

      assert_equal(1, logged.size, 'イベントを黙って捨てている')
      assert_equal('before_send', logged.first[:sentry])
    end

    # 🔴 **logger 自身が落ちても、どこかへ残すこと (#1549)。**
    # scrub が落ちる原因がマスク設定そのものなら、報告に使う `@logger.error` も
    # 同じ理由で落ちる。⚠ そこで黙ると「**Sentry へ 1 件も届かないのに、どこにも
    # 何も出ない**」＝ #1467 が塞ごうとした状態に戻る。マスク経路に依存しない
    # sink（素の `Syslog::Logger`）へ、例外のクラス名だけを出す。
    def test_scrub_reports_drop_when_logger_fails
      event = error_event(StandardError.new('boom'))
      event.define_singleton_method(:extra) {raise 'boom'}
      @scrubber.instance_variable_get(:@logger).define_singleton_method(:error) {|_arg| raise 'logger boom'}
      fallback = []
      @scrubber.define_singleton_method(:report_drop_fallback) do |error, log_error|
        fallback.push([error.class, log_error.class])
      end

      @scrubber.scrub(event)

      assert_equal(1, fallback.size, 'logger が落ちたときに何も残っていない')
    end

    # ⚠ 予備の sink は「マスク経路を通らないこと」と「クラス名しか出さないこと」
    # の両方が要る。⚠ **メッセージを載せると、伏せるはずだった値が素で出る。**
    def test_report_drop_fallback_emits_class_names_only
      written = []
      logger = Object.new
      logger.define_singleton_method(:error) {|arg| written.push(arg)}
      Syslog::Logger.define_singleton_method(:new) {|*| logger}
      begin
        @scrubber.send(:report_drop_fallback,
          Ginseng::GatewayError.new(WEBHOOK_URL), RuntimeError.new(FEED_TOKEN))
      ensure
        Syslog::Logger.singleton_class.remove_method(:new)
      end

      assert_equal(1, written.size)
      assert_include(written.first, 'Ginseng::GatewayError')
      assert_include(written.first, 'RuntimeError')
      assert_not_include(written.first, WEBHOOK_DIGEST)
      assert_not_include(written.first, FEED_TOKEN)
    end

    # ⚠ ログ自体が落ちても before_send を巻き込まないこと。
    def test_scrub_survives_logger_failure
      event = error_event(StandardError.new('boom'))
      event.define_singleton_method(:extra) {raise 'boom'}
      @scrubber.instance_variable_get(:@logger).define_singleton_method(:error) {|_arg| raise 'logger boom'}

      assert_nothing_raised {assert_nil(@scrubber.scrub(event))}
    end

    private

    # ⚠ **scrubber は setup で作ってある**（＝設定を変える前に掴んだ logger）。
    # ここで作り直すと、この検査の意味が無くなる。
    def scrubbed_probe
      event = error_event(StandardError.new('boom'))
      event.extra = {PROBE_FIELD => PROBE_VALUE}
      return payload(@scrubber.scrub(event))
    end

    # マスク対象を 1 つ足して `Config#reload` する。
    #
    # ⚠ **`raw` の鍵は設定ファイルの basename**（`local` / `application` / `lib` /
    # hostname）で、優先順は `Config#basenames` の順。`raw['logger']` へ書いても
    # 効かないし、低い側へ書いても高い側の値に上書きされる。**実在するうち
    # いちばん強い basename** へ足す。
    def with_mask_field(field)
      key = config.basenames.find {|v| config.raw.key?(v)}
      original = config.raw[key]['logger']
      config.raw[key]['logger'] = (original || {}).deep_dup
      config.raw[key]['logger']['mask_fields'] = config['/logger/mask_fields'] + [field]
      config.reload
      yield
    ensure
      config.raw[key]['logger'] = original
      config.reload
    end

    def error_event(error)
      client = Sentry::Client.new(sentry_configuration)
      return client.event_from_exception(error)
    end

    def sentry_configuration
      config = Sentry::Configuration.new
      config.dsn = 'https://publickey@example.com/1'
      config.environment = 'test'
      return config
    end

    # ⚠ **実際に送られる形（シリアライズ後）で見る。** アクセサ越しに 1 つずつ
    # 確かめると、見落とした欄がそのまま外へ出る。
    def payload(event)
      return event.to_json_compatible.to_json
    end
  end
end
