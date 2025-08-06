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

    def save_config
      puts config.secure_dump.to_yaml if config['/scheduler/verbose']
      super
    end

def fork!(args)
  Process.setsid
  exit if fork
  File.write(pid_file, Process.pid.to_s)
  Dir.chdir(working_dir)

  $stdout.reopen('/dev/null', 'w')
  $stderr.reopen('/dev/null', 'w')
  $stdout.sync = true
  $stderr.sync = true

  trap('TERM') do
    stop
    exit
  end
  start(args)
end

    def start(args)
      save_config
      logger.info(daemon: app_name, version: Package.version, message: 'start')

      #TomatoShrieker.setup_database
      #TomatoShrieker.loader.eager_load

      TomatoShrieker::Scheduler.instance.exec
      sleep
    rescue => e
      logger.error(daemon: app_name, error: e)
      raise
    end
  end
end
