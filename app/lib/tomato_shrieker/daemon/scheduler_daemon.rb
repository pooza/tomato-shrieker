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
      # ⚠ ここまでの HUP は queue に積むだけで、処理はしない。マイグレーションの
      # 前にジョブを立てると `no such table` を踏む。
      @reload_ready.push(true)
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
    def start_reload_worker
      @reload_queue = Thread::Queue.new
      @reload_ready = Thread::Queue.new
      trap('HUP') {@reload_queue.push(true)}
      @reload_thread = Thread.new {process_reloads if @reload_ready.pop}
    end

    # ⚠ `stop` が `close` すると `pop` は nil を返す。そこで抜ける。
    def process_reloads
      reload_once while @reload_queue.pop
    end

    # ⚠ **reload の失敗で daemon を落とさない。**壊れた YAML を掴んだだけなら
    # 古い定義のまま走り続けるのが正しい。
    def reload_once
      Scheduler.instance.reload
    rescue => e
      report_reload_failure(e)
    end

    # 🔴🔴 **ワーカーを絶対に死なせない (4.8.0 リリース前レビュー)。**
    #
    # 報告そのものが落ちると（`logger.error` が壊れた例外メッセージで落ちる形＝
    # #1469 の族。#1485 / #1549 が別経路で塞いだのと同じ）、例外が `while` を貫通して
    # **`process_reloads` を抜け、ワーカースレッドが終わる**。以後 trap は Queue に
    # 積み続けるが誰も pop しない ＝ **`source reload` は「reload requested」と言い、
    # daemon は健全に見えたまま、再起動するまで reload が二度と効かない。**
    # ⚠ `bin/scheduler_daemon.rb` が stderr を潰すので `report_on_exception` も出ない。
    #
    # ⚠ **出すのは例外のクラス名だけ。**メッセージを載せると、伏せるはずだった値を
    # マスク無しで書くことになる (#1549 と同じ判断)。
    def report_reload_failure(error)
      Sentry.capture_exception(error) if Sentry.initialized?
      logger.error(scheduler: 'reload', error:)
    rescue StandardError => e
      report_reload_fallback(error, e)
    end

    # 最後の 1 手はマスク経路にも Sentry にも依存させない (#1549 と同じ形)。
    def report_reload_fallback(error, log_error)
      ::Syslog::Logger.new(Package.name).error(
        "scheduler reload failed: #{error.class} (logging failed: #{log_error.class})",
      )
    rescue StandardError
      return nil
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
      @reload_ready&.close
      @monitor_server&.stop
      Scheduler.instance.scheduler.shutdown(:kill)
    end

    private

    # 🔴 **HUP の trap は pid が外から見えるより前に張る (#1545 Codex P2)。**
    # `bin/shrieker source reload` は pid ファイルを読んで HUP を送るので、
    # **書かれた瞬間から届きうる**。trap がまだ無ければ既定動作で daemon が死ぬ。
    # `start` の先頭で張っても窓は縮むだけで閉じない（実測 0.013ms・max 2.26ms）。
    #
    # ⚠ **`run_start` は override しない。**あちらの `abort_if_running!` /
    # TERM・INT の trap まで複製することになり、上流が #509 / #510 / #532 で
    # 個別に塞いだレースを写し取る羽目になる。pid を書く直前に通るのはここだけ
    # なので、1 行の `write_pid` を挟む。
    def write_pid
      start_reload_worker
      super
    end
  end
end
