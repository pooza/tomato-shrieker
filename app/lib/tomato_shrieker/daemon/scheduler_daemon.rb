module TomatoShrieker
  class SchedulerDaemon < Ginseng::Daemon
    include Package

    def command
      return nil
    end

    def motd
      return [
        "#{self.class} #{Package.version}",
        ('Ruby YJIT: Ready' if defined?(RubyVM::YJIT)),
      ].compact.join("\n")
    end

    def start(args)
      logger.info(daemon: app_name, version: Package.version, message: 'start')
      Sequel.connect(Environment.dsn)
      Scheduler.instance.exec
      sleep
    rescue => e
      logger.error(daemon: app_name, error: e)
      raise
    end
  end
end
