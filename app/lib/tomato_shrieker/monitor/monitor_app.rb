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
      source = Source.create(source_id)
      return [404, HEADERS, ["Unknown source: #{source_id}\n"]] unless source
      return [200, HEADERS, ["OK (not monitored)\n"]] unless source.monitored?
      latest = SourceRunLog.latest_for(source_id)
      return [503, HEADERS, ["No run recorded yet\n"]] unless latest
      next_run = source.next_run_at(latest.executed_at)
      stale = Time.now > next_run + source.monitor_grace_seconds
      # 単発の失敗では倒さず、配信試行ベースの連続エラーで判定する (#1457)。
      # no-op run は streak を切らさないので、直近が no-op でも継続失敗を見逃さない。
      streak = SourceRunLog.error_streak(source_id)
      errored = streak >= error_streak_threshold
      silent = source.silent?
      return [200, HEADERS, ["OK\n"]] unless stale || errored || silent
      return [503, HEADERS, [unhealthy_body(source, latest, {next_run:, stale:, streak:, silent:})]]
    end

    def unhealthy_body(source, latest, checks)
      body = "status: #{latest.status}\n"
      body << "executed_at: #{latest.executed_at.iso8601}\n"
      body << "next_run_at: #{checks[:next_run].iso8601}\n"
      body << "grace_seconds: #{source.monitor_grace_seconds}\n"
      body << "stale: #{checks[:stale]}\n"
      body << "error_streak: #{checks[:streak]}\n"
      body << "error: #{latest.error_message}\n" if latest.error?
      return body unless checks[:silent]
      # #1470: 配信できていないこと自体を出す
      body << "silent: true\n"
      body << "last_delivered_at: #{source.last_delivered_at&.iso8601}\n"
      body << "silence_tolerance_seconds: #{source.monitor_silence_tolerance_seconds}\n"
      body << "noop_streak: #{SourceRunLog.noop_streak(source.id)}\n"
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
      return [500, JSON_HEADERS, ["#{JSON.dump(error: "#{e.class}: #{e.message}")}\n"]]
    end

    def source_status(source)
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
      return SourceRunLog.summary_for(source.id).merge(
        last_attempted_count: latest&.attempted_count,
        last_delivered_count: latest&.delivered_count,
        last_delivered_at: source.last_delivered_at&.iso8601,
        last_delivered_at_origin: source.last_delivered_at_origin,
        silence_tolerance_seconds: source.monitor_silence_tolerance_seconds,
        silent: source.silent?,
        error_rate_24h: SourceRunLog.error_rate(source.id),
      )
    end

    def error_streak_threshold
      return Config.instance['/monitor/error_streak_threshold'] || 1
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
