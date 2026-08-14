module TomatoShrieker
  class SchedulerDaemonTest < TestCase
    def setup
      @daemon = SchedulerDaemon.new
      @path = File.join(Environment.dir, 'tmp/db', "__test_scheduler_daemon_#{Process.pid}.sqlite3")
      FileUtils.rm_f(@path)
    end

    def teardown
      FileUtils.rm_f(@path)
      super
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
