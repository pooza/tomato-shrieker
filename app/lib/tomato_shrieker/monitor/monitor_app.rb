module TomatoShrieker
  class MonitorApp
    HEADERS = {'content-type' => 'text/plain; charset=utf-8'}.freeze

    def call(env)
      case env['PATH_INFO']
      when '/healthz'
        healthz
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
      if checks.values.all?
        return [200, HEADERS, ["OK\n"]]
      end
      body = checks.map {|k, v| "#{k}: #{v ? 'OK' : 'FAIL'}"}.join("\n") + "\n"
      return [503, HEADERS, [body]]
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
