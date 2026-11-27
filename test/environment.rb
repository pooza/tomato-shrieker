module TomatoShrieker
  class EnvironmentTest < TestCase
    def setup
      @path = File.join(Environment.dir, 'tmp/db', "__test_environment_#{Process.pid}.sqlite3")
      FileUtils.rm_f(@path)
    end

    def teardown
      @db&.disconnect
      @holder&.close
      FileUtils.rm_f(@path)
    end

    # #1806: 書き込みの錠を待つあいだ、ほかのスレッドが止まらない（GVL を手放して待つ）。
    # ⚠ Sequel 既定の `busy_timeout` だと、待つ側が GVL を握ったまま眠るので、錠を持つ側
    # （ここでは main スレッド）も進めず、5 秒後に BUSY で落ちる。
    def test_connect_database_waits_without_holding_gvl
      @db = Environment.connect_database("sqlite://#{@path}")
      @db.run('CREATE TABLE t (v INTEGER)')
      @holder = SQLite3::Database.new(@path)
      @holder.execute('BEGIN IMMEDIATE')
      max_gap = 0
      beat = Thread.new do
        last = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        loop do
          sleep(0.01)
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          max_gap = [max_gap, now - last].max
          last = now
        end
      end
      writer = Thread.new {@db[:t].insert(v: 1)}
      sleep(1)
      @holder.commit
      writer.join
      beat.kill

      assert_equal(1, @db[:t].count)
      assert_operator(max_gap, :<, 0.5)
    end
  end
end
