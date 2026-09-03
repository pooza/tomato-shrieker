module TomatoShrieker
  class SchedulerTest < TestCase
    # config/sources は環境ごとに中身が違うので、テスト専用の定義を置いてから確かめる。
    FIXTURE_ID = '__test_scheduler__'.freeze
    OTHER_ID = '__test_scheduler_other__'.freeze
    ICAL_ID = '__test_scheduler_ical__'.freeze
    BROKEN_ID = '__test_scheduler_broken__'.freeze
    IDS = [FIXTURE_ID, OTHER_ID, ICAL_ID, BROKEN_ID].freeze

    # teardown は異常終了で走らない。config/sources/.gitignore が `*` なので取り残しは
    # git status にも出ず、次のスケジューラ起動で偽ソースとして登録されてしまう。
    at_exit do
      Dir.glob(File.join(Environment.dir, 'config/sources', '__test_scheduler*.yaml'))
        .each {|f| FileUtils.rm_f(f)}
    end

    def setup
      @scheduler = Scheduler.instance
      IDS.each {|id| FileUtils.rm_f(fixture_path(id))}
      write_fixture(FIXTURE_ID, {})
      @scheduler.reload
    end

    def teardown
      IDS.each {|id| FileUtils.rm_f(fixture_path(id))}
      # ⚠ Scheduler は Singleton なので、テストが張ったジョブは以後もプロセスに残る。
      @scheduler.scheduler.jobs.each(&:unschedule)
      @scheduler.registry.clear
      super # TestCase#teardown が config.reload する
    end

    def fixture_path(id)
      return File.join(Environment.dir, 'config/sources', "#{id}.yaml")
    end

    def write_fixture(id, extra)
      values = {
        'source' => {'feed' => "https://example.com/#{id}.rss"},
        'schedule' => {'every' => '1d'},
        'dest' => {'hooks' => ["https://example.com/#{id}/hook"]},
      }.deep_merge(extra)
      File.write(fixture_path(id), YAML.dump(values))
    end

    def jobs(id)
      return @scheduler.scheduler.jobs(tag: id)
    end

    def test_reload_adds_source
      assert_empty(jobs(OTHER_ID))
      write_fixture(OTHER_ID, {})
      result = @scheduler.reload

      assert_equal(1, jobs(OTHER_ID).size)
      assert_include(result[:added], OTHER_ID)
    end

    def test_reload_removes_source
      assert_equal(1, jobs(FIXTURE_ID).size)
      FileUtils.rm_f(fixture_path(FIXTURE_ID))
      result = @scheduler.reload

      assert_empty(jobs(FIXTURE_ID))
      assert_include(result[:removed], FIXTURE_ID)
    end

    def test_reload_replaces_changed_source
      write_fixture(FIXTURE_ID, {'schedule' => {'every' => '2d'}})
      result = @scheduler.reload

      assert_equal(1, jobs(FIXTURE_ID).size)
      assert_equal('2d', jobs(FIXTURE_ID).first.original)
      assert_include(result[:changed], FIXTURE_ID)
    end

    # 🔴 **無変更のソースはジョブに触らない。**`every` は差し替えると次回発火が
    # 1 周期先へずれるので、全件を貼り替えると全ソースの位相がリセットされる。
    def test_reload_keeps_unchanged_job
      job = jobs(FIXTURE_ID).first
      write_fixture(OTHER_ID, {}) # 別のソースを足しても FIXTURE_ID には波及しない
      result = @scheduler.reload

      assert_equal(job.job_id, jobs(FIXTURE_ID).first.job_id)
      assert_equal(job.next_time, jobs(FIXTURE_ID).first.next_time)
      assert_not_include(result[:changed], FIXTURE_ID)
    end

    def test_reload_disable_and_enable
      write_fixture(FIXTURE_ID, {'disable' => true})
      @scheduler.reload

      assert_empty(jobs(FIXTURE_ID))

      write_fixture(FIXTURE_ID, {})
      result = @scheduler.reload

      assert_equal(1, jobs(FIXTURE_ID).size)
      assert_include(result[:added], FIXTURE_ID)
    end

    # ⚠ prune の日次ジョブは**無タグ**。「全部 unschedule」をやると巻き添えで消える。
    def test_reload_keeps_untagged_maintenance_job
      @scheduler.send(:schedule_maintenance)
      untagged = @scheduler.scheduler.jobs.reject {|v| v.tags.any?}

      assert_not_empty(untagged)
      # ⚠ 差分が無いと unschedule 自体が走らない。追加と変更の両方を起こしてから見る。
      write_fixture(OTHER_ID, {})
      write_fixture(FIXTURE_ID, {'schedule' => {'every' => '2d'}})
      @scheduler.reload

      assert_equal(untagged.map(&:job_id).sort,
        @scheduler.scheduler.jobs.reject {|v| v.tags.any?}.map(&:job_id).sort)
    end

    # ⚠ IcalendarSource は remind と本体の 2 本を同じ tag で登録する。
    # job id を控える設計にすると remind ジョブが取り残される。
    def test_reload_replaces_both_icalendar_jobs
      write_ical_fixture('4 0 * * *')
      @scheduler.reload

      assert_equal(2, jobs(ICAL_ID).size)
      before = jobs(ICAL_ID).map(&:job_id)
      write_ical_fixture('5 0 * * *')
      @scheduler.reload

      assert_equal(2, jobs(ICAL_ID).size)
      assert_empty(jobs(ICAL_ID).map(&:job_id) & before)
    end

    # 🔴 **register が失敗したソースは、古いジョブを残す (#1545 Codex P1)。**
    # reload はスキーマ検証をしないので、不正な cron 式はここまで来る。先に
    # unschedule する実装だと、失敗したソースが次の reload までジョブ 1 本無い
    # まま放置される（daemon 側は例外を握って走り続けるので誰も気付けない）。
    def test_reload_keeps_old_jobs_when_register_fails
      job = jobs(FIXTURE_ID).first
      write_fixture(FIXTURE_ID, {'schedule' => {'cron' => 'not a cron'}})
      result = @scheduler.reload

      assert_include(result[:failed], FIXTURE_ID)
      assert_equal(1, jobs(FIXTURE_ID).size)
      assert_equal(job.job_id, jobs(FIXTURE_ID).first.job_id)
    end

    # 失敗した id は registry を更新しないので、直せば次の reload で必ず張り直る。
    def test_reload_retries_failed_source
      write_fixture(FIXTURE_ID, {'schedule' => {'cron' => 'not a cron'}})
      @scheduler.reload
      write_fixture(FIXTURE_ID, {'schedule' => {'every' => '2d'}})
      result = @scheduler.reload

      assert_empty(result[:failed])
      assert_equal('2d', jobs(FIXTURE_ID).first.original)
    end

    # 1 ソースの失敗で他のソースの反映を止めない。
    def test_reload_isolates_failed_source
      write_fixture(FIXTURE_ID, {'schedule' => {'cron' => 'not a cron'}})
      write_fixture(OTHER_ID, {})
      result = @scheduler.reload

      assert_include(result[:failed], FIXTURE_ID)
      assert_include(result[:added], OTHER_ID)
      assert_equal(1, jobs(OTHER_ID).size)
    end

    # ⚠ **初回登録も同じ差分適用を通す (#1545 Codex P1)。**SIGHUP は起動の途中から
    # 受け付けるので、両方が素通しで register するとジョブが 2 本立ち、以後は
    # digest が一致するので誰も気付けない。
    def test_register_all_after_reload_does_not_duplicate
      job = jobs(FIXTURE_ID).first
      @scheduler.send(:register_all)

      assert_equal(1, jobs(FIXTURE_ID).size)
      assert_equal(job.job_id, jobs(FIXTURE_ID).first.job_id)
    end

    # 🔴 壊れた定義を掴んだら、ジョブは 1 本も触らずに古い定義のまま走り続ける。
    def test_reload_keeps_jobs_when_config_is_broken
      job = jobs(FIXTURE_ID).first
      File.write(fixture_path(BROKEN_ID), "source:\n  feed: \"unterminated\n")

      assert_raise(Psych::SyntaxError) {@scheduler.reload}
      assert_equal(1, jobs(FIXTURE_ID).size)
      assert_equal(job.job_id, jobs(FIXTURE_ID).first.job_id)
    end

    private

    def write_ical_fixture(cron)
      File.write(fixture_path(ICAL_ID), YAML.dump({
        'source' => {'ical' => 'https://example.com/calendar.ics'},
        'schedule' => {'cron' => cron, 'remind' => {'enable' => true}},
        'dest' => {'hooks' => ["https://example.com/#{ICAL_ID}/hook"]},
      }))
    end
  end
end
