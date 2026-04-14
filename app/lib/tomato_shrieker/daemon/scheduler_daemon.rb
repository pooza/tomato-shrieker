module TomatoShrieker
  class SchedulerDaemon < Ginseng::Daemon
    include Package

    def command
      return nil
    end

    def motd
      return [
        "#{self.class} #{Package.version}",
        ('Ruby YJIT: Ready' if Environment.jit?),
      ].compact.join("\n")
    end

    def start(args = [])
      logger.info(daemon: app_name, version: Package.version, message: 'start')
      db = Sequel.connect(Environment.dsn)
      db.run('PRAGMA journal_mode=WAL')
      db.run('PRAGMA busy_timeout=5000')
      @monitor_server = MonitorServer.new
      @monitor_server.start
      Scheduler.instance.exec
    rescue => e
      Sentry.capture_exception(e) if Sentry.initialized?
      logger.error(daemon: app_name, error: e)
      raise
    end

    def stop
      logger.info(daemon: app_name, version: Package.version, message: 'stop')
      @monitor_server&.stop
      Scheduler.instance.scheduler.shutdown(:kill)
    end
  end
end
