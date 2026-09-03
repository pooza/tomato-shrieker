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
      start_reload_worker
      Scheduler.instance.exec
    rescue => e
      Sentry.capture_exception(e) if Sentry.initialized?
      logger.error(daemon: app_name, error: e)
      raise
    end

    # SIGHUP でソース定義を読み直す (#1459)。`bin/shrieker source reload` が送る。
    #
    # ⚠ **trap 文脈では Mutex を取れない**（`ThreadError`）。`Scheduler#reload` は
    # Mutex を取るので、**trap は Queue に積むだけ**にして専用スレッドが処理する。
    #
    # ⚠ `Ginseng::Daemon#run_start` は override しない。あちらの `abort_if_running!` /
    # `write_pid` / TERM・INT の trap を複製することになる。ここで張れば足りる。
    def start_reload_worker
      @reload_queue = Thread::Queue.new
      @reload_thread = Thread.new do
        # ⚠ `stop` が `close` すると `pop` は nil を返す。そこで抜ける。
        while @reload_queue.pop
          begin
            Scheduler.instance.reload
          rescue => e
            # ⚠ **reload の失敗で daemon を落とさない。**壊れた YAML を掴んだだけなら
            # 古い定義のまま走り続けるのが正しい。
            Sentry.capture_exception(e) if Sentry.initialized?
            logger.error(scheduler: 'reload', error: e)
          end
        end
      end
      trap('HUP') {@reload_queue.push(true)}
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
      @reload_queue&.close
      @monitor_server&.stop
      Scheduler.instance.scheduler.shutdown(:kill)
    end
  end
end
