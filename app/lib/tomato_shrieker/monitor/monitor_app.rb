# frozen_string_literal: true

require 'json'

module TomatoShrieker
  class MonitorApp
    HEADERS = {'content-type' => 'text/plain; charset=utf-8'}.freeze
    JSON_HEADERS = {'content-type' => 'application/json; charset=utf-8'}.freeze
    SOURCE_HEALTHZ = %r{\A/healthz/source/(?<id>[^/]+)\z}

    def call(env)
      path = env['PATH_INFO']
      case path
      when '/healthz'
        healthz
      when '/status.json'
        status_json
      when SOURCE_HEALTHZ
        healthz_source(Regexp.last_match(:id))
      else
        [404, HEADERS, ["Not Found\n"]]
      end
    end

    private

    def healthz
      checks = {
        scheduler: scheduler_alive?,
        database: database_alive?,
      }
      return [200, HEADERS, ["OK\n"]] if checks.values.all?
      body = "#{checks.map {|k, v| "#{k}: #{v ? 'OK' : 'FAIL'}"}.join("\n")}\n"
      return [503, HEADERS, [body]]
    end

    # ⚠ **503 を返すなら Sentry にも出す（4.8.0 リリース前レビュー）。**#1485 で
    # 「`/healthz` を 503 にするのに Sentry へ出ないエラーを作らない」と決めたのに、
    # 監視コード自身の失敗だけが例外になっていた。
    def healthz_source(source_id)
      return build_healthz_source(source_id)
    rescue => e
      if Sentry.initialized?
        Sentry.capture_exception(e, tags: {source: source_id, stage: 'healthz'})
      end
      return [503, HEADERS, ["#{Package.error_message(e)}\n"]]
    end

    def build_healthz_source(source_id)
      source = Source.create(source_id)
      return [404, HEADERS, ["Unknown source: #{source_id}\n"]] unless source
      # 意図的に止めたソースを「壊れている」と混同しない (#1503)。
      return [200, HEADERS, ["OK (disabled)\n"]] if source.disable?
      return [200, HEADERS, ["OK (not monitored)\n"]] unless source.monitored?
      # 宛先ゼロは実行結果を見るまでもなく壊れている (#1473)。
      # ⚠ 無効ソースはここまで来ない (#1503)。スキーマが disable: true のとき dest の
      # 必須を免除している (chinachu 等の死蔵定義が実際に dest: {}) 件 (#1486) も、
      # 「無効なら監視しない」で一括して片付く。
      return [503, HEADERS, ["No destination configured\n"]] unless source.dest?
      latest = SourceRunLog.latest_for(source_id)
      return [503, HEADERS, ["No run recorded yet\n"]] unless latest
      checks = source_checks(source, latest)
      return [200, HEADERS, ["OK\n"]] unless unhealthy?(checks)
      return [503, HEADERS, [unhealthy_body(source, latest, checks)]]
    end

    def source_checks(source, latest)
      next_run = source.next_run_at(latest.executed_at)
      # 連続エラーで判定する (#1457)。何回で倒すかは error_streak_threshold で調整する。
      # ⚠ **しきい値はソース単位で上書きできる (#1558)。**読む行数もそれに従わせないと、
      # しきい値だけ大きくしても窓が足りず、到達し得ないまま健全扱いになる。
      logs = SourceRunLog.recent_for(
        source.id, SourceRunLog.streak_window(source.monitor_error_streak_threshold)
      )
      streak = SourceRunLog.error_streak_of(logs)
      threshold = effective_error_streak_threshold(source, logs)
      return {
        next_run:,
        stale: Time.now > next_run + source.monitor_grace_seconds,
        streak:,
        threshold:,
        errored: streak >= threshold,
        silent: source.silent?,
        # 試みたのに届かなかった宛先がある (#1504)。取りこぼしは再送されないので、
        # 次に全宛先へ届くか、運用者が確認するまで解除しない (#1506)。
        # ⚠ opt-in の silent? と違い、しきい値の設定なしに常時有効。
        # 判定は Source 側に寄せてある。
        undelivered: (source.undelivered_log if source.undelivered?),
      }
    end

    # 🔴🔴 **緩和を効かせてよい失敗かを見てから、しきい値を決める (#1558)。**
    #
    # ⚠⚠ **エントリを読んだ後に落ちた失敗は 1 回で赤にする。**緩めるとそのぶんの
    # エントリが**恒久的に失われる**（`Entry.insert` は配信より先・unique 制約で
    # 再取得されない）のに、`undelivered` / `stale` / `silent` のどれも立たないので
    # **`error_streak` が唯一のゲート**になっている（#1473）。
    #
    # 📌 緩められるのは「エントリを 1 件も読めていない失敗」＝フィード取得そのものの
    # 失敗だけ。#1558 の動機である YouTube の 404 はこちら。
    def effective_error_streak_threshold(source, logs)
      return 1 if SourceRunLog.entry_level_error?(logs)
      return source.monitor_error_streak_threshold
    end

    def unhealthy?(checks)
      return true if checks[:stale] || checks[:errored] || checks[:silent]
      return !checks[:undelivered].nil?
    end

    def unhealthy_body(source, latest, checks)
      body = "status: #{latest.status}\n"
      body << "executed_at: #{latest.executed_at.iso8601}\n"
      body << "next_run_at: #{checks[:next_run].iso8601}\n"
      body << "grace_seconds: #{source.monitor_grace_seconds}\n"
      body << "stale: #{checks[:stale]}\n"
      body << "error_streak: #{checks[:streak]} / #{checks[:threshold]}\n"
      body << failure_body(latest)
      body << undelivered_body(checks[:undelivered], latest) if checks[:undelivered]
      body << silent_body(source) if checks[:silent]
      return body
    end

    # 🔴 **失敗の理由は status に関係なく出す (#1507)。**
    #
    # 以前は `latest.error?`（＝ `status == "error"`）でだけ出していた。⚠ #1482 で
    # `partial` を分けた時点で、**Matrix 配信停止 (#1455) と同じ形の run は
    # `partial` になり、理由がまったく出ない 503** になっていた（v4.5.0 からの後退）。
    # `record_partial` は「status が error でないだけで、失敗は失敗として読める
    # ようにする」ために `error_message` を残しているので、それを出す。
    #
    # ⚠⚠ **宛先ごとの識別子は出さない。**webhook の URL はパスそのものが資格情報
    # (#1467)。`shrieker_errors` なら宛先の**種別**までは絞れて、識別子は載らない。
    def failure_body(log, prefix = '')
      body = +''
      body << "#{prefix}error: #{log.error_message}\n" if log.error_message.present?
      errors = log.shrieker_error_counts
      body << "#{prefix}shrieker_errors: #{JSON.dump(errors)}\n" if errors.any?
      return body
    end

    # #1470: 配信できていないこと自体を出す
    def silent_body(source)
      # ⚠ `+` を付けて可変にする (#1512)。式展開の無いリテラルは将来 frozen に
      # なるので、`<<` すると FrozenError で healthz_source の rescue に落ち、
      # **503 の本文が診断情報を丸ごと失う**（ステータスは 503 のままなので
      # Kuma は気づかない）。
      body = +"silent: true\n"
      body << "last_delivered_at: #{source.last_delivered_at&.iso8601}\n"
      body << "silence_tolerance_seconds: #{source.monitor_silence_tolerance_seconds}\n"
      body << "noop_streak: #{SourceRunLog.noop_streak(source.id)}\n"
      # #1505: 静かなだけと分かっているなら `bin/shrieker source ack ID` で緑に戻せる
      body << "silence_baseline: #{source.silence_baseline&.iso8601}\n"
      body << "silence_baseline_origin: #{source.silence_baseline_origin}\n"
      body << "silence_acknowledged_at: #{SilenceAck.acknowledged_at(source.id)&.iso8601}\n"
      return body
    end

    # #1504: 「いつ・何件のうち何件が届かなかったか」を運用者に見せる。
    # ⚠ 宛先の識別子は持たないので「どの宛先か」は出せない。設定を見て切り分ける。
    def undelivered_body(log, latest)
      # ⚠ 式展開の無いリテラルなので `+` で可変にする (#1512)。上の silent_body 参照。
      body = +"undelivered: true\n"
      body << "last_attempted_at: #{log.executed_at.iso8601}\n"
      body << "attempted_count: #{log.attempted_count}\n"
      body << "delivered_count: #{log.delivered_count}\n"
      # 🔴 **no-op を挟むと `latest` は success の no-op 行になる (#1507)。**
      # そのとき理由を持っているのは `latest` ではなく「直近の配信試行」の行なので、
      # ここでも出す。⚠ 同じ行なら上の failure_body と重複するので出さない。
      return body if log.id == latest.id
      body << "last_attempted_status: #{log.status}\n"
      body << failure_body(log, 'last_attempted_')
      return body
    end

    def status_json
      sources = Source.all.reject(&:disable?).map {|s| source_status(s)}
      payload = {
        scheduler: scheduler_alive?,
        database: database_alive?,
        # ⚠ 情報として出すだけで判定はしない (#1471)。詳細は Environment.ruby_health。
        ruby: Environment.ruby_health,
        sources:,
      }
      return [200, JSON_HEADERS, ["#{JSON.pretty_generate(payload)}\n"]]
    rescue => e
      Sentry.capture_exception(e, tags: {stage: 'status_json'}) if Sentry.initialized?
      return [500, JSON_HEADERS, ["#{JSON.dump(error: Package.error_message(e))}\n"]]
    end

    # 1 ソースの失敗で payload 全体を落とさない。壊れた側は error として可視化する。
    #
    # 🔴 **ここが最も静かに壊れる（4.8.0 リリース前レビュー）。**返る行が
    # `{id, class, error}` の 3 キーに退化するので、**`undelivered` / `silent` が
    # キーごと消える**。`sources[].undelivered == true` を探す消費者はそのソースを
    # 「異常なし」と読む。⚠ 総合 `/healthz` は scheduler と database しか見ないので
    # 200 のまま ＝ **Kuma 未登録のソースでは誰にも届かない** (#1508)。
    def source_status(source)
      return build_source_status(source)
    rescue => e
      if Sentry.initialized?
        Sentry.capture_exception(e, tags: {source: source.id, stage: 'status_json'})
      end
      return {id: source.id, class: source.class.to_s, error: Package.error_message(e)}
    end

    def build_source_status(source)
      latest = SourceRunLog.latest_for(source.id)
      next_run = (source.next_run_at(latest.executed_at) if source.monitored? && latest)
      {
        id: source.id,
        class: source.class.to_s,
        schedule: source.schedule_spec,
        grace_seconds: source.monitor_grace_seconds,
        last_run_at: latest&.executed_at&.iso8601,
        next_run_at: next_run&.iso8601,
        last_status: latest&.status,
        last_error: latest&.error_message,
        last_duration_ms: latest&.duration_ms,
      }.merge(delivery_status(source, latest))
    end

    # #1433 (統計) と #1470 (サイレント不発) の指標。
    def delivery_status(source, latest)
      attempted = SourceRunLog.last_attempted(source.id)
      # 🔴 **窓もしきい値も /healthz/source/:id と完全に同じものを使う（Codex P2・#1558）。**
      # 既定の窓はグローバルのしきい値しか見ないので、ソース側で sample_size (50) を
      # 超える値に上書きすると **503 にしている当人が `error_streak: 50 / 100` という
      # 自己矛盾した数字を出す**。⚠⚠ **しきい値も「宣言値」ではなく実効値を出す。**
      # `effective_error_streak_threshold` が 1 に倒している場合、宣言値を出すと
      # `/healthz` が `1 / 1` で 503 なのに `/status.json` は `4` と言う。
      # ⚠ **2 つのエンドポイントが同名フィールドで違う数字を出す**のは 4.8.0 の
      # レビューで `last_attempted_count` で潰した型の不具合なので、繰り返さない。
      logs = SourceRunLog.recent_for(
        source.id, SourceRunLog.streak_window(source.monitor_error_streak_threshold)
      )
      return SourceRunLog.summary_of(logs).merge(
        dest_count: source.dest_count,
        # #1504: 直近の配信試行の内訳。undelivered が true なら未解決の取りこぼしがある
        last_attempted_at: attempted&.executed_at&.iso8601,
        # ⚠ 確認済みなら false になる (#1506)。なぜ緑なのかは silence_acknowledged_at で読む
        undelivered: source.undelivered?,
        # 🔴 **`attempted` から出す（4.8.0 リリース前レビュー）。**`latest` は
        # **直近の run** なので、no-op を挟むと **`last_attempted_at` は前の試行を
        # 指しているのに件数だけ 0** という自己矛盾になる。⚠ 本番で再現した:
        # `capsicum` が `/status.json` で 0/0、同じ行が DB では 1/1。
        # ⚠ `/healthz/source/:id` の 503 本文は `attempted` 側から出しているので、
        # **2 つのエンドポイントが同名フィールドで違う数字**を出していた。
        last_attempted_count: attempted&.attempted_count,
        last_delivered_count: attempted&.delivered_count,
        last_delivered_at: source.last_delivered_at&.iso8601,
        last_delivered_at_origin: source.last_delivered_at_origin,
        silence_tolerance_seconds: source.monitor_silence_tolerance_seconds,
        # 🔴 **3 値 (#1502)。**`null` は「まだ判定できない」＝ run_log 上に配信実績も
        # 確認記録も無く、観測開始からしきい値も経っていない。⚠ 以前は `false` が
        # 「健全」と「判定不能」を兼ねていて、外から区別できなかった。
        silent: source.silent?,
        # なぜその判定なのか。`observation` なら下限（観測開始からの経過）に頼っている
        silence_baseline: source.silence_baseline&.iso8601,
        silence_baseline_origin: source.silence_baseline_origin,
        # #1505: 「なぜ緑なのか」を答えられるようにする。確認済みなら silent は
        # false だが、それは健全だからではなく運用者が確認したから
        silence_acknowledged_at: SilenceAck.acknowledged_at(source.id)&.iso8601,
        error_rate_24h: SourceRunLog.error_rate(source.id),
        # #1558: 「なぜこのソースはまだ緑なのか」を外から説明できるようにする
        error_streak_threshold: effective_error_streak_threshold(source, logs),
      )
    end

    def scheduler_alive?
      scheduler = Scheduler.instance.scheduler
      return false unless scheduler
      return false if scheduler.down?
      return scheduler.jobs.any?
    rescue StandardError
      return false
    end

    def database_alive?
      Entry.db.test_connection
      return true
    rescue StandardError
      return false
    end
  end
end
