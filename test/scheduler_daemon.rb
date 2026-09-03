module TomatoShrieker
  class SchedulerDaemonTest < TestCase
    def setup
      @daemon = SchedulerDaemon.new
      @path = File.join(Environment.dir, 'tmp/db', "__test_scheduler_daemon_#{Process.pid}.sqlite3")
      # ⚠ 本物の pid ファイルを書かない。開発機で稼働中の daemon を指す pid を
      # 上書きすると、次の stop / restart が別プロセスを掴む。
      @pid_path = File.join(Environment.dir, 'tmp/pids', "__test_scheduler_daemon_#{Process.pid}.pid")
      FileUtils.rm_f(@path)
      FileUtils.rm_f(@pid_path)
    end

    def teardown
      FileUtils.rm_f(@path)
      FileUtils.rm_f(@pid_path)
      @daemon.instance_variable_get(:@reload_queue)&.close
      @daemon.instance_variable_get(:@reload_ready)&.close
      @daemon.instance_variable_get(:@reload_thread)&.join(5)
      trap('HUP', 'DEFAULT')
      @stubbed&.singleton_class&.remove_method(:reload)
      super
    end

    # #1459: SIGHUP でソース定義を読み直す。
    # ⚠ **trap 文脈では Mutex を取れない**（`ThreadError`）。`Scheduler#reload` は
    # Mutex を取るので、trap は Queue に積むだけにして専用スレッドが処理する。
    # ここで確かめているのは「HUP がワーカー経由で reload に届く」配線。
    def test_reload_worker_handles_sighup
      calls = Thread::Queue.new
      stub_reload {calls.push(:called)}
      @daemon.send(:start_reload_worker)
      ready
      Process.kill('HUP', Process.pid)

      assert_equal(:called, calls.pop(timeout: 10))
    end

    # 🔴 **trap は pid を書く前に張るが、処理は起動完了後 (#1545 Codex P2)。**
    # `write_pid` が pid を書いた瞬間から `source reload` は HUP を送れるので、
    # trap が無ければ既定動作で daemon が死ぬ。⚠ とはいえマイグレーション前に
    # ジョブを立てると `no such table` を踏むので、届いても積むだけにする。
    def test_reload_worker_defers_until_ready
      calls = Thread::Queue.new
      stub_reload {calls.push(:called)}
      @daemon.send(:start_reload_worker)
      Process.kill('HUP', Process.pid)

      assert_nil(calls.pop(timeout: 1))
      ready

      assert_equal(:called, calls.pop(timeout: 10))
    end

    # 🔴 **reload の失敗で daemon を落とさない。**壊れた YAML を掴んだだけなら
    # 古い定義のまま走り続けるのが正しく、次の reload 要求も処理できねばならない。
    def test_reload_worker_survives_error
      calls = Thread::Queue.new
      stub_reload do
        calls.push(:called)
        raise 'boom'
      end
      @daemon.send(:start_reload_worker)
      ready
      queue = @daemon.instance_variable_get(:@reload_queue)
      queue.push(true)

      assert_equal(:called, calls.pop(timeout: 10))
      queue.push(true)

      assert_equal(:called, calls.pop(timeout: 10))
    end

    # 🔴 **pid が外から見えた時点で trap が張られていること (#1545 Codex P2)。**
    # `bin/shrieker source reload` は pid ファイルを読んで HUP を送るので、
    # `start` の先頭で張るのでは間に合わないことがある（窓が縮むだけで閉じない）。
    #
    # ⚠ **観測点は `pid_file`。**上流の `write_pid` は `File.write` の直前にこれを
    # 呼ぶので、**pid が公開される瞬間の trap の状態**はここでしか見られない。
    def test_write_pid_installs_hup_trap_before_publishing
      observed = nil
      path = @pid_path
      @daemon.define_singleton_method(:pid_file) do
        # ⚠ `trap` は現在のハンドラを返すが同時に差し替えるので、読んだら戻す。
        observed ||= trap('HUP', 'DEFAULT').tap {|prev| trap('HUP', prev)}
        path
      end
      @daemon.send(:write_pid)

      assert_equal(Process.pid.to_s, File.read(path))
      assert_not_equal('DEFAULT', observed)
    end

    # 起動完了の合図。SchedulerDaemon#start では monitor server を上げた直後に押す。
    def ready
      @daemon.instance_variable_get(:@reload_ready).push(true)
    end

    def stub_reload(&)
      @stubbed = Scheduler.instance
      @stubbed.define_singleton_method(:reload, &)
    end

    def migration_dir
      return File.join(Environment.dir, 'app/migration')
    end

    # #1410 で rake start/restart を廃止したとき migration:run が一緒に落ちていた。
    # スキーマが古いまま起動すると実行時に分かりにくい形で壊れる。
    def test_migrate
      db = Sequel.connect("sqlite://#{@path}")

      assert_false(Sequel::Migrator.is_current?(db, migration_dir))
      @daemon.migrate(db)

      assert_true(Sequel::Migrator.is_current?(db, migration_dir))
      assert_include(db[:source_run_log].columns, :delivered_count)
    end

    # 010 と 011 が同時に走る環境 (4.4.0 から直接上げた場合) では、
    # 既存行はすべて配信計測より前なので 1 行も残してはいけない。
    # 残すと observed_since が計測前まで遡り、silence_tolerance を設定したソースが
    # 上げた直後に赤くなる。
    def test_migrate_drops_rows_written_before_delivery_stats
      db = Sequel.connect("sqlite://#{@path}")
      Sequel::Migrator.run(db, migration_dir, target: 9)
      db[:source_run_log].insert(source_id: 'test', executed_at: Time.now - 3600, status: 'success')

      @daemon.migrate(db)

      assert_equal(0, db[:source_run_log].count)
    end

    # 計測が始まった後の行は残す。010 を適用したまま動き続けた環境で、
    # 上げた瞬間に観測実績を丸ごと失わないため。
    def test_migrate_keeps_rows_written_after_delivery_stats
      db = Sequel.connect("sqlite://#{@path}")
      Sequel::Migrator.run(db, migration_dir, target: 10)
      logs = db[:source_run_log]
      logs.insert(source_id: 'test', executed_at: Time.now - 7200, status: 'success')
      logs.insert(source_id: 'test', executed_at: Time.now - 3600, status: 'success', attempted_count: 1, delivered_count: 1)
      logs.insert(source_id: 'test', executed_at: Time.now - 60, status: 'success')

      @daemon.migrate(db)

      assert_equal(2, logs.count)
      assert_equal(1, logs.order(:executed_at).first[:attempted_count])
    end

    # 起動のたびに走るので、適用済みでも無害でなければならない
    def test_migrate_idempotent
      db = Sequel.connect("sqlite://#{@path}")
      @daemon.migrate(db)
      version = db[:schema_info].first[:version]
      @daemon.migrate(db)

      assert_equal(version, db[:schema_info].first[:version])
    end
  end
end
