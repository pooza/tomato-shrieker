module TomatoShrieker
  class SchedulerDaemon < Ginseng::Daemon
    include Package

    def command
      return nil
    end

    def motd
      return [
        "#{self.class} #{Package.version}",
        ('Ruby YJIT: Ready' if jit_ready?),
      ].compact.join("\n")
    end

    def start(args)
      logger.info(daemon: app_name, version: Package.version, message: 'start')
      Sequel::Model.db = Sequel.connect(Environment.dsn)
      TomatoShrieker::Scheduler.instance.exec
      sleep
    rescue => e
      logger.error(daemon: app_name, error: e)
      raise
    end
  end
end
