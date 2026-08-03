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
