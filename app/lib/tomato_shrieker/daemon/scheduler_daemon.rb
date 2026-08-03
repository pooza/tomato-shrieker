Sequel.extension(:migration)

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
      migrate(db)
      @monitor_server = MonitorServer.new
      @monitor_server.start
      Scheduler.instance.exec
    rescue => e
      Sentry.capture_exception(e) if Sentry.initialized?
      logger.error(daemon: app_name, error: e)
      raise
    end

    # #1410 で rake start/restart を廃止したとき、その前提タスクだった migration:run が
    # 一緒に落ちて手動になっていた。スキーマが古いまま起動すると実行時に分かりにくい形で
    # 壊れるので、ここで揃える。失敗したら起動させない。
    def migrate(db)
      return if Sequel::Migrator.is_current?(db, migration_dir)
      logger.info(daemon: app_name, message: 'migration start')
      Sequel::Migrator.run(db, migration_dir)
      logger.info(daemon: app_name, message: 'migration done')
    end

    def migration_dir
      return File.join(Environment.dir, 'app/migration')
    end

    def stop
      logger.info(daemon: app_name, version: Package.version, message: 'stop')
      @monitor_server&.stop
      Scheduler.instance.scheduler.shutdown(:kill)
    end
  end
end
