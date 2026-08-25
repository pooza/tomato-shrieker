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

    def healthz_source(source_id)
      return build_healthz_source(source_id)
    rescue => e
      return [503, HEADERS, ["#{Package.error_message(e)}\n"]]
    end

    def build_healthz_source(source_id)
      source = Source.create(source_id)
      return [404, HEADERS, ["Unknown source: #{source_id}\n"]] unless source
      return [200, HEADERS, ["OK (not monitored)\n"]] unless source.monitored?
      # 宛先ゼロは実行結果を見るまでもなく壊れている (#1473)。
      # ⚠ 無効ソースは除く。スキーマが disable: true のとき dest の必須を免除しており
      # (chinachu 等の死蔵定義が実際に dest: {})、ランタイムだけ咎めると食い違う (#1486)。
      return [503, HEADERS, ["No destination configured\n"]] unless source.dest? || source.disable?
      latest = SourceRunLog.latest_for(source_id)
      return [503, HEADERS, ["No run recorded yet\n"]] unless latest
      checks = source_checks(source, latest)
      return [200, HEADERS, ["OK\n"]] unless unhealthy?(checks)
      return [503, HEADERS, [unhealthy_body(source, latest, checks)]]
    end

    def source_checks(source, latest)
      next_run = source.next_run_at(latest.executed_at)
      # 連続エラーで判定する (#1457)。何回で倒すかは error_streak_threshold で調整する。
      streak = SourceRunLog.error_streak(source.id)
      return {
        next_run:,
        stale: Time.now > next_run + source.monitor_grace_seconds,
        streak:,
        errored: streak >= error_streak_threshold,
        silent: source.silent?,
        # 試みたのに届かなかった宛先がある (#1504)。取りこぼしは再送されないので、
        # 次に全宛先へ届くまで解除しない。⚠ opt-in の silent? と違い常時有効。
        undelivered: SourceRunLog.last_attempted(source.id),
      }
    end

    def unhealthy?(checks)
      return true if checks[:stale] || checks[:errored] || checks[:silent]
      return checks[:undelivered]&.undelivered? || false
    end

    def unhealthy_body(source, latest, checks)
      body = "status: #{latest.status}\n"
      body << "executed_at: #{latest.executed_at.iso8601}\n"
      body << "next_run_at: #{checks[:next_run].iso8601}\n"
      body << "grace_seconds: #{source.monitor_grace_seconds}\n"
      body << "stale: #{checks[:stale]}\n"
      body << "error_streak: #{checks[:streak]}\n"
      body << "error: #{latest.error_message}\n" if latest.error?
      body << undelivered_body(checks[:undelivered]) if checks[:undelivered]&.undelivered?
      body << silent_body(source) if checks[:silent]
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
      body << "silence_acknowledged_at: #{SilenceAck.acknowledged_at(source.id)&.iso8601}\n"
      return body
    end

    # #1504: 「いつ・何件のうち何件が届かなかったか」を運用者に見せる。
    # ⚠ 宛先の識別子は持たないので「どの宛先か」は出せない。設定を見て切り分ける。
    def undelivered_body(log)
      # ⚠ 式展開の無いリテラルなので `+` で可変にする (#1512)。上の silent_body 参照。
      body = +"undelivered: true\n"
      body << "last_attempted_at: #{log.executed_at.iso8601}\n"
      body << "attempted_count: #{log.attempted_count}\n"
      body << "delivered_count: #{log.delivered_count}\n"
      return body
    end

    def status_json
      sources = Source.all.reject(&:disable?).map {|s| source_status(s)}
      payload = {
        scheduler: scheduler_alive?,
        database: database_alive?,
        sources:,
      }
      return [200, JSON_HEADERS, ["#{JSON.pretty_generate(payload)}\n"]]
    rescue => e
      return [500, JSON_HEADERS, ["#{JSON.dump(error: Package.error_message(e))}\n"]]
    end

    # 1 ソースの失敗で payload 全体を落とさない。壊れた側は error として可視化する。
    def source_status(source)
      return build_source_status(source)
    rescue => e
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
      return SourceRunLog.summary_for(source.id).merge(
        dest_count: source.dest_count,
        # #1504: 直近の配信試行の内訳。undelivered が true なら未解決の取りこぼしがある
        last_attempted_at: attempted&.executed_at&.iso8601,
        undelivered: attempted&.undelivered? || false,
        last_attempted_count: latest&.attempted_count,
        last_delivered_count: latest&.delivered_count,
        last_delivered_at: source.last_delivered_at&.iso8601,
        last_delivered_at_origin: source.last_delivered_at_origin,
        silence_tolerance_seconds: source.monitor_silence_tolerance_seconds,
        silent: source.silent?,
        # #1505: 「なぜ緑なのか」を答えられるようにする。確認済みなら silent は
        # false だが、それは健全だからではなく運用者が確認したから
        silence_acknowledged_at: SilenceAck.acknowledged_at(source.id)&.iso8601,
        error_rate_24h: SourceRunLog.error_rate(source.id),
      )
    end

    def error_streak_threshold
      return Config.instance['/monitor/error_streak_threshold']
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
