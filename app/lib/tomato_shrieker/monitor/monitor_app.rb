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
      body = checks.map {|k, v| "#{k}: #{v ? 'OK' : 'FAIL'}"}.join("\n") + "\n"
      return [503, HEADERS, [body]]
    end

    def healthz_source(source_id)
      source = Source.create(source_id)
      return [404, HEADERS, ["Unknown source: #{source_id}\n"]] unless source
      tolerance = source.run_tolerance_seconds
      return [200, HEADERS, ["OK (not monitored)\n"]] unless tolerance
      latest = SourceRunLog.latest_for(source_id)
      return [503, HEADERS, ["No run recorded yet\n"]] unless latest
      stale = Time.now - latest.executed_at > tolerance
      errored = latest.status == SourceRunLog::STATUS_ERROR
      return [200, HEADERS, ["OK\n"]] unless stale || errored
      body = +"status: #{latest.status}\n"
      body << "executed_at: #{latest.executed_at.iso8601}\n"
      body << "tolerance_seconds: #{tolerance}\n"
      body << "stale: #{stale}\n"
      body << "error: #{latest.error_message}\n" if errored
      return [503, HEADERS, [body]]
    end

    def status_json
      sources = Source.all.reject(&:disable?).map {|s| source_status(s)}
      payload = {
        scheduler: scheduler_alive?,
        database: database_alive?,
        sources:,
      }
      return [200, JSON_HEADERS, [JSON.pretty_generate(payload) + "\n"]]
    rescue => e
      return [500, JSON_HEADERS, [JSON.dump(error: "#{e.class}: #{e.message}") + "\n"]]
    end

    def source_status(source)
      latest = SourceRunLog.latest_for(source.id)
      {
        id: source.id,
        class: source.class.to_s,
        schedule: source.schedule_spec,
        tolerance_seconds: source.run_tolerance_seconds,
        last_run_at: latest&.executed_at&.iso8601,
        last_status: latest&.status,
        last_error: latest&.error_message,
        last_duration_ms: latest&.duration_ms,
      }
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
