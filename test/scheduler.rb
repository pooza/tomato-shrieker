module TomatoShrieker
  class SchedulerTest < TestCase
    # config/sources は環境ごとに中身が違うので、テスト専用の定義を置いてから確かめる。
    FIXTURE_ID = '__test_scheduler__'.freeze
    OTHER_ID = '__test_scheduler_other__'.freeze
    ICAL_ID = '__test_scheduler_ical__'.freeze
    BROKEN_ID = '__test_scheduler_broken__'.freeze
    IDS = [FIXTURE_ID, OTHER_ID, ICAL_ID, BROKEN_ID].freeze

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
      return File.join(Config.scratch_sources_dir, "#{id}.yaml")
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

    # #1686: ジョブの登録時刻。⚠ 同じ tag のジョブ（IcalendarSource のリマインドなど）はいちばん古いもの。
    def test_registered_at
      at = @scheduler.registered_at(FIXTURE_ID)

      assert_kind_of(Time, at)
      assert_in_delta(Time.now.to_f, at.to_f, 60)
      assert_nil(@scheduler.registered_at(OTHER_ID))
    end

    # ⚠ 起動の登録が倒れたら、待ち受けに入ったことにしない（`exec` の頭で立てない）。
    def test_not_serving_without_run_jobs
      assert_false(@scheduler.serving?)
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

    # 🔴 **#1571: 同じ id の定義が 2 つある状態で片方を消したら、digest に差が出る。**
    #
    # ⚠ 以前は `sources.first` だけをハッシュしていたので、group が [A, B] → [A] に
    # 縮んでも digest は SHA1(A) のまま＝ `stale` に入らず、**消したほうのジョブが
    # unschedule されずに走り続ける**。⚠⚠ ログの `changed` / `removed` にも出ないので、
    # 運用者は「反映済み」と読む＝**侵害された宛先を外そうとしたときに効かない形**。
    def test_reload_detects_shrinking_duplicate_id_group
      # ⚠ ファイル名ではなくトップレベル `id:` で衝突させる（Config は `id` が
      # 無いときだけファイル名を入れる）。
      write_fixture(OTHER_ID, {'id' => FIXTURE_ID})
      @scheduler.reload

      assert_equal(2, jobs(FIXTURE_ID).size, '重複した id が 2 本のジョブとして立っていない')

      FileUtils.rm_f(fixture_path(OTHER_ID))
      result = @scheduler.reload

      assert_include(result[:changed], FIXTURE_ID)
      assert_equal(1, jobs(FIXTURE_ID).size, '消したほうのジョブが残っている')
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

    # 🔴 **#1572: 判別キーの typo を「削除」と読まない。**
    #
    # reload は意図的にスキーマ検証をしないので、YAML として妥当なまま
    # `source/feed` を打ち間違える / 消すことができる。⚠ そうすると `Source.all` が
    # その定義を 1 件も yield せず、`desired_sources` から id ごと消える。
    # ⚠⚠ 素直に読むと `drop_removed` が**意図的な削除として unschedule** し、
    # ログにも `removed` と出る＝**「消した覚えはないのに消えている」**になる。
    def test_reload_keeps_jobs_when_source_class_does_not_match
      job = jobs(FIXTURE_ID).first
      File.write(fixture_path(FIXTURE_ID), YAML.dump(
        'source' => {'feeed' => 'https://example.com/typo.rss'},
        'schedule' => {'every' => '1d'},
        'dest' => {'hooks' => ['https://example.com/hook']},
      ))
      result = @scheduler.reload

      assert_include(result[:unmatched], FIXTURE_ID)
      assert_not_include(result[:removed], FIXTURE_ID, 'typo が削除として扱われている')
      assert_equal(1, jobs(FIXTURE_ID).size, '古いジョブが残っていない')
      assert_equal(job.job_id, jobs(FIXTURE_ID).first.job_id)
    end

    # 🔴 **4.10.0 リリース前レビュー: unmatched は `failed` と同じく Sentry へ出すこと。**
    # 古いジョブが古い定義のまま走り続けるのに、以前は `logger.info` にしか出なかった。
    def test_reload_reports_unmatched_to_sentry
      File.write(fixture_path(FIXTURE_ID), YAML.dump(
        'source' => {'feeed' => 'https://example.com/typo.rss'},
        'schedule' => {'every' => '1d'},
        'dest' => {'hooks' => ['https://example.com/hook']},
      ))
      captured = []
      with_sentry_stub(captured) {@scheduler.reload}

      assert_equal([FIXTURE_ID], captured.map {|v| v.dig(:tags, :source)})
      assert_include(captured.first[:error].message, 'no source class matched')
    end

    # ⚠ **本当にファイルを消したときは、これまでどおり削除する。**上の fail safe が
    # 「消しても消えない」に化けていないこと。
    def test_reload_still_removes_deleted_source
      FileUtils.rm_f(fixture_path(FIXTURE_ID))
      result = @scheduler.reload

      assert_include(result[:removed], FIXTURE_ID)
      assert_empty(jobs(FIXTURE_ID))
    end

    # 🔴 **起動は fail closed。**定義は在るのに 1 件も yield されないものを飛ばすと、
    # 「永久に走らないのに daemon は正常に見える」が残る（`failed` を倒す理由と同じ）。
    def test_register_all_raises_when_source_class_does_not_match
      File.write(fixture_path(OTHER_ID), YAML.dump(
        'source' => {'feeed' => 'https://example.com/typo.rss'},
        'dest' => {'hooks' => ['https://example.com/hook']},
      ))
      config.reload
      @scheduler.registry.clear

      error = assert_raise(Ginseng::ConfigError) {@scheduler.send(:register_all)}

      assert_include(error.message, OTHER_ID)
      assert_include(error.message, 'no source class matched')
    end

    # 🔴 **4.10.0 リリース前レビュー 赤 B（#1589 Codex P1）: `disable: true` は
    # unmatched の逃げ道として効くこと。**
    #
    # ⚠⚠ typo に気付いた運用者が `source disable` すると、以前は unmatched に数えられた
    # ままで **reload は古いジョブを守り続け、起動は倒れた**。
    def test_reload_removes_disabled_unmatched_source
      File.write(fixture_path(FIXTURE_ID), YAML.dump(
        'disable' => true,
        'source' => {'feeed' => 'https://example.com/typo.rss'},
        'schedule' => {'every' => '1d'},
        'dest' => {'hooks' => ['https://example.com/hook']},
      ))
      result = @scheduler.reload

      assert_not_include(result[:unmatched], FIXTURE_ID)
      assert_include(result[:removed], FIXTURE_ID)
      assert_empty(jobs(FIXTURE_ID))
    end

    def test_register_all_ignores_disabled_unmatched_source
      File.write(fixture_path(OTHER_ID), YAML.dump(
        'disable' => true,
        'source' => {'feeed' => 'https://example.com/typo.rss'},
        'dest' => {'hooks' => ['https://example.com/hook']},
      ))
      config.reload
      @scheduler.registry.clear

      assert_nothing_raised {@scheduler.send(:register_all)}
    end

    # 🔴 **起動時の register 失敗は握らない (#1547 Codex P1)。**reload と違い、
    # ここで飛ばすとそのソースは二度と登録されないまま daemon が正常に見える
    # （総合 /healthz は無タグの maintenance ジョブがあれば通る）。倒しておけば
    # systemd の `Restart=always` が再試行する。⚠ **起動は fail closed、
    # reload は fail safe。**
    # 🔴🔴 **`exec` 経由で倒れること（4.8.0 リリース前レビュー）。**
    #
    # ⚠ `register_all` を直接叩くテストだけだと**この穴を判別できない**。
    # `Ginseng::ConfigError` も `StandardError` なので、`exec` に `rescue => e` が
    # あると **「起動時の失敗は握らない」(#1547) が丸ごと無効化され**、プロセスは
    # 終了コード 0 で落ちる（`systemctl status` 上は正常停止と区別がつかない）。
    # ⚠ `Scheduler` は Singleton なので、差し替えたメソッドは必ず外すこと。
    # 残すと後続のテストが巻き添えになる（実際に踏んだ）。
    def test_exec_does_not_swallow_register_failure
      @scheduler.define_singleton_method(:register_all) do
        raise Ginseng::ConfigError, 'failed to register: x'
      end
      @scheduler.define_singleton_method(:run_jobs) {nil}

      assert_raise_kind_of(Ginseng::ConfigError) {@scheduler.exec}
    ensure
      [:register_all, :run_jobs].each do |name|
        @scheduler.singleton_class.remove_method(name) if @scheduler.singleton_methods.include?(name)
      end
    end

    def test_register_all_raises_when_register_fails
      write_fixture(OTHER_ID, {'schedule' => {'cron' => 'not a cron'}})
      config.reload
      @scheduler.registry.clear

      error = assert_raise(Ginseng::ConfigError) {@scheduler.send(:register_all)}

      assert_include(error.message, OTHER_ID)
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

    # 🔴 **#1529: 読んだ回数と結果を持つ。**`source reload --wait` が `count` の前進を待つ。
    def test_load_state
      before = @scheduler.load_state[:count]
      write_fixture(OTHER_ID, {})
      @scheduler.reload
      state = @scheduler.load_state

      assert_equal(before + 1, state[:count])
      assert_equal('reload', state[:action])
      assert_include(state[:result][:added], OTHER_ID)
      assert_nil(state[:error])
    end

    # ⚠ **失敗しても `count` は進む**（進まないと `--wait` が締切まで待つ）。メッセージは載せない。
    def test_load_state_records_failure
      before = @scheduler.load_state[:count]
      File.write(fixture_path(BROKEN_ID), "source:\n  feed: \"unterminated\n")
      assert_raise(Psych::SyntaxError) {@scheduler.reload}
      state = @scheduler.load_state

      assert_equal(before + 1, state[:count])
      assert_equal('Psych::SyntaxError', state[:error])
      assert_nil(state[:result])
    end

    # #1717 の Codex P2: 古いジョブの取得そのものが落ちたら、巻き戻さない（既存のジョブを残す）。
    def test_swap_keeps_jobs_when_lookup_fails
      job = jobs(FIXTURE_ID).first
      rufus = @scheduler.scheduler
      original = rufus.method(:jobs)
      calls = 0
      rufus.define_singleton_method(:jobs) do |*args, **kwargs|
        calls += 1
        raise 'lookup failed' if calls == 1
        original.call(*args, **kwargs)
      end
      source = Source.all.find {|v| v.id == FIXTURE_ID}

      assert_false(@scheduler.send(:swap, FIXTURE_ID, [source], 'reload'))
      rufus.singleton_class.remove_method(:jobs)

      assert_equal([job.job_id], jobs(FIXTURE_ID).map(&:job_id))
    ensure
      rufus.singleton_class.remove_method(:jobs) if rufus&.singleton_methods&.include?(:jobs)
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

    # ⚠ 元の Method を保存して差し戻す（`Sentry.initialized?` は Sentry 自身の singleton class に
    # 生えているので、`remove_method` で戻すと本物ごと消える）。
    def with_sentry_stub(captured)
      originals = [:initialized?, :capture_exception].to_h {|name| [name, Sentry.method(name)]}
      Sentry.define_singleton_method(:initialized?) {true}
      Sentry.define_singleton_method(:capture_exception) do |error, **options|
        captured.push({error:}.merge(options))
      end
      yield
    ensure
      originals&.each {|name, method| Sentry.define_singleton_method(name, method)}
    end
  end
end
