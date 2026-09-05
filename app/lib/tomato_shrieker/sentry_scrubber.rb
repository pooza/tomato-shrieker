module TomatoShrieker
  # Sentry へ送るイベントから資格情報を落とす (#1467)。
  #
  # 🔴 **ログでは伏せている値が、例外イベントとしては素通りしていた。**
  # `sentry-ruby` の `send_default_pii` は既定 false だが、守られるのは
  # リクエストヘッダ等であって、**アプリが自分で例外メッセージへ埋めた値**は
  # 対象外。tomato はまさにそれをやっている。
  #
  #   raise Ginseng::GatewayError, "Invalid feed #{id} (#{uri}) #{e.message}"
  #
  # ⚠⚠ **マスクの正本は `Ginseng::Logger`。** ここで同等品を書くと、対象の列が
  # ログ側と 2 か所に分かれて必ずズレる。`/logger/mask_fields` /
  # `/logger/mask_query_params` / `/logger/mask_url_paths` を唯一の正本に保つため、
  # gem 側の `mask` / `mask_url` をそのまま呼ぶ（pooza/ginseng-core#580 で public
  # になった）。
  class SentryScrubber
    include Package

    # ⚠ **ここで logger を掴んでおく。** イベントごとに new すると、マスク設定の
    # 読み出しがイベント送信時の文脈に移る。初期化時に解決しておけば、設定が
    # 読めないときは Sentry ごと立ち上がらない（fail closed）。
    def initialize
      @logger = logger
      # 設定が読めることをここで確かめる。⚠ 読めないまま before_send に入ると、
      # 「マスク対象ゼロ ＝ 素通し」で送り続けることになる。
      @logger.mask_url('https://example.com/?token=probe')
    end

    # ⚠ **必ず event を返すこと。** `before_send` が `Sentry::ErrorEvent` 以外を
    # 返すとイベントは破棄される（sentry-ruby 6.6.2 の client.rb）。
    def scrub(event)
      scrub_exceptions(event)
      event.message = mask(event.message) if event.message.is_a?(String)
      event.transaction = mask(event.transaction) if event.transaction.is_a?(String)
      event.extra = mask(event.extra)
      event.tags = mask(event.tags)
      event.contexts = mask(event.contexts)
      event.user = mask(event.user)
      scrub_breadcrumbs(event)
      return event
    rescue => e
      # 🔴 **fail closed。** マスクを通せなかったイベントは送らない。
      # 素通しで送ると、伏せるはずだった値がそのまま外部サービスへ出る。
      report_drop(e)
      return nil
    end

    private

    # 🔴 **`warn` で出してはいけない。** `bin/scheduler_daemon.rb` が
    # `$stderr.reopen(File::NULL)` するので、**本番では丸ごと消える**。
    # ここが見えないと「scrub が壊れて Sentry へ何も届かないのに、誰も気づけない」
    # という #1467 の目的と正反対の状態になる。
    #
    # ⚠ ログ自体が落ちても before_send を巻き込まない（イベントは落とす側に倒す）。
    def report_drop(error)
      @logger.error(sentry: 'before_send', message: 'event dropped (scrub failed)', error:)
    rescue StandardError => e
      report_drop_fallback(error, e)
    end

    # 🔴 **報告の最後の 1 手はマスク経路に依存させない (#1549)。**
    # scrub が落ちる原因がマスク設定そのものなら、`@logger.error` も同じ理由で
    # 落ちる。⚠ そこを黙って捨てると「**Sentry へ 1 件も届かないのに、どこにも
    # 何も出ない**」＝ #1467 が塞ごうとした状態に戻る。
    #
    # ⚠ **出すのは例外のクラス名だけ。**メッセージを載せると、伏せるはずだった
    # 値をマスク無しで書くことになる。
    # ⚠ **`warn` は使えない。**`bin/scheduler_daemon.rb` が
    # `$stderr.reopen(File::NULL)` するので本番では丸ごと消える。
    def report_drop_fallback(error, log_error)
      ::Syslog::Logger.new(Package.name).error(
        'sentry before_send: event dropped (scrub failed):' \
          " #{error.class} (logging failed: #{log_error.class})",
      )
    rescue StandardError
      return nil
    end

    # 例外メッセージ本体。⚠ **ここが tomato でいちばん漏れる場所。**
    # `SingleExceptionInterface#value` だけが writable。
    def scrub_exceptions(event)
      # ⚠ 局所変数へ受けてから回す。`event.exception` は Hash ではなく
      # `Sentry::ExceptionInterface`（`values` は Array）なので、`each_value` は
      # 生えていない。RuboCop の Style/HashEachMethods を誤爆させないため。
      entries = event.exception&.values
      return unless entries
      entries.each do |entry|
        entry.value = mask(entry.value) if entry.value.is_a?(String)
      end
    end

    def scrub_breadcrumbs(event)
      event.breadcrumbs&.buffer&.each do |crumb|
        next unless crumb
        crumb.message = mask(crumb.message) if crumb.message.is_a?(String)
        crumb.data = mask(crumb.data) if crumb.data.is_a?(Hash)
      end
    end

    # ⚠ `Ginseng::Logger#mask` は Hash / Array / String を再帰的に処理し、
    # `mask_fields` のキーは**値ごと落とす**。String は `mask_url` を通る。
    def mask(value)
      return value unless value.is_a?(String) || value.is_a?(Hash) || value.is_a?(Array)
      return @logger.mask(value)
    end
  end
end
