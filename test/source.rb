module TomatoShrieker
  class SourceTest < TestCase
    RETRY_ID = '__test_source_retry__'.freeze

    def test_all
      Source.all do |source|
        assert_kind_of(Source, source)
      end
    end

    def test_to_h
      Source.all do |source|
        assert_kind_of(Hash, source.to_h)
      end
    end

    def test_disable?
      Source.all do |source|
        assert_boolean(source.disable?)
      end
    end

    def test_mulukhiya?
      Source.all do |source|
        assert_boolean(source.mulukhiya?)
      end
    end

    def test_test?
      Source.all do |source|
        assert_boolean(source.test?)
      end
    end

    def test_bot?
      Source.all do |source|
        assert_boolean(source.bot?)
      end
    end

    def test_templates
      Source.all do |source|
        assert_kind_of(Hash, source.templates)
        assert_kind_of(Template, source.templates[:default])
      end
    end

    def test_create_template
      Source.all do |source|
        assert_kind_of(Template, source.create_template)
        assert_kind_of(Template, source.create_template(:default))
        # 呼ぶたびに別インスタンスでないと Parallel.each で壊し合う (#1474)
        assert_not_same(source.create_template, source.create_template)
      end
    end

    def test_dest_count
      Source.all do |source|
        assert_kind_of(Integer, source.dest_count)
        assert_operator(source.dest_count, :>=, 0)
        assert_equal(source.dest_count.positive?, source.dest?)
      end
    end

    def test_dest_count_counts_every_kind
      source = TextSource.new({
        'id' => 'test-dest-count',
        'source' => {'text' => 'body'},
        'dest' => {
          'hooks' => ['https://example.com/a', 'https://example.com/b'],
          'mastodon' => {'url' => 'https://example.com', 'token' => 't'},
        },
      })

      assert_equal(3, source.dest_count)
      assert_true(source.dest?)
    end

    # /status.json は全ソース分を毎回組み立てる。数えるだけで宛先へ接続してはいけない
    def test_dest_count_does_not_instantiate_shriekers
      source = TextSource.new({
        'id' => 'test-dest-count-piefed',
        'source' => {'text' => 'body'},
        'dest' => {
          'piefed' => {
            'host' => 'piefed.example.com', 'user_id' => 'u',
            'password' => 'p', 'community_id' => 1
          },
        },
      })

      assert_equal(1, source.dest_count)
      # piefed? を経由していれば PiefedShrieker#initialize の login で通信が起きる
      assert_nil(source.instance_variable_get(:@piefed))
    end

    # 🔴 **#1712 の Codex P1: 宛先のオブジェクトは run ごとに作り直す。**スケジューラのソースは
    # run をまたいで生きるので、作り直さないと PieFed の期限切れの JWT がずっと残る。
    def test_exec_with_run_log_resets_shriekers
      id = '__test_source_reset_shriekers__'
      source = TextSource.new({
        'id' => id,
        'source' => {'text' => 'body'},
        'dest' => {'mastodon' => {'url' => 'https://mastodon.example.test', 'token' => 'token-0123'}},
      })
      source.define_singleton_method(:exec) {nil}
      first = source.mastodon

      assert_same(first, source.mastodon, 'run の中では共有する')
      source.send(:exec_with_run_log, :every, '5m')

      assert_not_same(first, source.mastodon)
    ensure
      SourceRunLog.where(source_id: id).delete
    end

    # 🔴 **#1585: 1 件も配信できずに落ちた run は、`schedule.retry` があればやり直す。**
    def test_retry_failed_run
      source = retry_source({'times' => 2, 'interval' => '10m'}) {raise 'upstream is down'}

      assert_equal(0, retry_jobs.size)
      source.send(:exec_with_run_log, :cron, '1 0 * * *')

      assert_equal(1, retry_jobs.size)
      # ⚠ 上限（times）に達したら、もうやり直さない。
      source.send(:exec_with_run_log, :retry, 2, attempt: 2)

      assert_equal(1, retry_jobs.size)
    ensure
      cleanup_retry
    end

    # やり直しのジョブが実際に走り、run_log に 1 行ずつ残る。上限で止まる。
    def test_retry_runs_and_stops
      source = retry_source({'times' => 1, 'interval' => '0.3s'}) {raise 'upstream is down'}
      source.send(:exec_with_run_log, :cron, '1 0 * * *')
      deadline = Time.now + 5
      sleep(0.1) while SourceRunLog.where(source_id: RETRY_ID).count < 2 && Time.now < deadline

      assert_equal(2, SourceRunLog.where(source_id: RETRY_ID).count)
      assert_equal(0, retry_jobs.size)
    ensure
      cleanup_retry
    end

    # 🔴 **#1741 の Codex P1: やり直しと定期実行が重なっても、互いの集計を上書きしない。**
    # ⚠ ゆっくり落ちる run の最中に、すぐ配信できる run が割り込む形。直列にしないと、落ちた run が
    # 割り込んだ run の集計（配信 1 件）を読み、やり直さない。
    def test_runs_are_serialized
      source = retry_source({}) do
        raise 'upstream is down' unless Thread.current[:fast]
        @delivery_stats.record_success(Object.new)
      end
      slow = source.method(:exec)
      source.define_singleton_method(:exec) do
        sleep(0.3) unless Thread.current[:fast]
        slow.call
      end
      failing = Thread.new {source.send(:exec_with_run_log, :cron, '1 0 * * *')}
      sleep(0.1)
      Thread.new do
        Thread.current[:fast] = true
        source.send(:exec_with_run_log, :cron, '1 0 * * *')
      end.join
      failing.join

      assert_equal(1, retry_jobs.size)
    ensure
      cleanup_retry
    end

    # 🔴 **#1741 の Codex P2: daemon の中では、定義が変わった・消えたソースのやり直しを捨てる。**
    def test_retry_dropped_when_definition_is_gone
      source = retry_source({}) {nil}
      scheduler = Scheduler.instance

      assert_true(source.send(:current_definition?), 'daemon の外では見ない')
      scheduler.define_singleton_method(:serving?) {true}

      assert_false(source.send(:current_definition?))
      ran = false
      source.define_singleton_method(:exec_with_run_log) {|*| ran = true}
      source.send(:exec_retry, 1)

      assert_false(ran)
    ensure
      scheduler.singleton_class.send(:remove_method, :serving?) if scheduler.singleton_methods.include?(:serving?)
      cleanup_retry
    end

    # ⚠ 宛先で全部落ちた（配信 0 件の error）run もやり直す。
    def test_retry_when_nothing_delivered
      source = retry_source({}) {@delivery_stats.record_error(Object.new, RuntimeError.new('500'))}
      source.send(:exec_with_run_log, :cron, '1 0 * * *')

      assert_equal(1, retry_jobs.size)
    ensure
      cleanup_retry
    end

    # ⚠ #1741 の Codex P2: FeedSource 系はエントリの段に入った後の失敗をやり直さない（記録済みとして
    # 飛ばすので、やり直しても何も出ない）。段に入る前（取得の失敗）はやり直す。
    def test_feed_retries_only_fetch_failures
      params = {
        'id' => RETRY_ID,
        'source' => {'feed' => 'https://example.com/retry.rss'},
        'schedule' => {'every' => '1d', 'retry' => {}},
        'dest' => {'hooks' => ['https://hook.example.test/retry']},
      }
      source = FeedSource.new(params)
      source.define_singleton_method(:exec) do
        @delivery_stats.enter_entry_stage!
        @delivery_stats.record_error(Object.new, RuntimeError.new('500'))
      end
      source.send(:exec_with_run_log, :every, '1d')

      assert_equal(0, retry_jobs.size)
      source.define_singleton_method(:exec) {raise 'feed is down'}
      source.send(:exec_with_run_log, :every, '1d')

      assert_equal(1, retry_jobs.size)
    ensure
      cleanup_retry
    end

    # 🔴 **1 件でも配信していたらやり直さない。**届いた宛先へもう一度投稿することになる。
    def test_no_retry_after_partial_delivery
      source = retry_source({}) do
        @delivery_stats.record_success(Object.new)
        raise 'failed after posting'
      end
      source.send(:exec_with_run_log, :cron, '1 0 * * *')

      assert_equal(0, retry_jobs.size)
    ensure
      cleanup_retry
    end

    # ⚠ 書いていないソース（既定）と、成功した run はやり直さない。
    def test_no_retry_without_config_or_on_success
      retry_source(nil) {raise 'upstream is down'}.send(:exec_with_run_log, :cron, '1 0 * * *')
      retry_source({}) {nil}.send(:exec_with_run_log, :cron, '1 0 * * *')

      assert_equal(0, retry_jobs.size)
    ensure
      cleanup_retry
    end

    # 🔴 **#1712 の Codex P2: 宛先を取り出している途中に、作り直しが割り込まない。**
    # `IcalendarSource` は日次の実行とリマインドが別々のジョブで、どちらも始めに
    # `reset_shriekers` する。割り込まれると、`mastodon?` と `mastodon` の間で nil を掴む。
    # ⚠ 偶然の競合では再現しない（GVL の下では窓が小さい）ので、取り出しの途中で止めて確かめる。
    def test_reset_waits_for_shrieker_snapshot
      source = TextSource.new({
        'id' => '__test_source_concurrent_reset__',
        'source' => {'text' => 'body'},
        'dest' => {'mastodon' => {'url' => 'https://mastodon.example.test', 'token' => 'token-0123'}},
      })
      entered = Thread::Queue.new
      release = Thread::Queue.new
      original = source.method(:mastodon)
      source.define_singleton_method(:mastodon) do
        entered.push(true)
        release.pop
        original.call
      end
      reader = Thread.new {source.shriekers.to_a}
      entered.pop
      reset_done = false
      resetter = Thread.new do
        source.reset_shriekers
        reset_done = true
      end
      sleep(0.2)

      assert_false(reset_done, '取り出しの途中で作り直された')
      2.times {release.push(true)}

      assert_equal(1, reader.value.size)
      resetter.join

      assert_true(reset_done)
    end

    # #1473: token を消したような半端な宛先を 1 と数えると、shriekers が 0 件なのに
    # dest? が真になり、塞いだはずの「永久に no-op success」がそのまま残る
    def test_dest_count_requires_complete_destination
      [
        ['mastodon', {'url' => 'https://example.com'}],
        ['misskey', {'url' => 'https://example.com'}],
        ['line', {'user_id' => 'u'}],
        ['piefed', {'host' => 'h', 'user_id' => 'u', 'password' => 'p'}],
        ['nostr', {'relays' => ['wss://example.com']}],
      ].each do |kind, incomplete|
        source = TextSource.new({
          'id' => "test-dest-incomplete-#{kind}",
          'source' => {'text' => 'body'},
          'dest' => {kind => incomplete},
        })

        assert_equal(0, source.dest_count, "#{kind} の不完全な設定を宛先として数えている")
        assert_false(source.dest?)
      end
    end

    # 必須キーが揃っていれば数える。DEST_KINDS が各アクセサのガード条件から
    # ずれていないことの担保（⚠ shriekers を呼ぶと piefed の login で通信するので使わない）
    def test_dest_count_accepts_complete_destination
      [
        ['mastodon', {'url' => 'https://example.com', 'token' => 't'}],
        ['misskey', {'url' => 'https://example.com', 'token' => 't'}],
        ['line', {'user_id' => 'u', 'token' => 't'}],
        ['piefed', {'host' => 'h', 'user_id' => 'u', 'password' => 'p', 'community_id' => 1}],
        ['nostr', {'private_key' => 'k'}],
      ].each do |kind, complete|
        source = TextSource.new({
          'id' => "test-dest-complete-#{kind}",
          'source' => {'text' => 'body'},
          'dest' => {kind => complete},
        })

        assert_equal(1, source.dest_count, "#{kind} の完全な設定を宛先として数えていない")
        assert_true(source.dest?)
      end
    end

    def test_dest_count_ignores_non_destination_keys
      source = TextSource.new({
        'id' => 'test-dest-count-empty',
        'source' => {'text' => 'body'},
        'dest' => {'tags' => ['a'], 'template' => 'common'},
      })

      assert_equal(0, source.dest_count)
      assert_false(source.dest?)
    end

    def test_spoiler_text
      Source.all do |source|
        assert_kind_of([String, NilClass], source.spoiler_text)
      end
    end

    def test_mastodon
      Source.all do |source|
        assert_boolean(source.mastodon?)
        next unless source.mastodon?

        assert_kind_of(MastodonShrieker, source.mastodon)
      end
    end

    def test_misskey
      Source.all do |source|
        assert_boolean(source.misskey?)
        next unless source.misskey?

        assert_kind_of(MisskeyShrieker, source.misskey)
      end
    end

    def test_line
      Source.all do |source|
        assert_boolean(source.line?)
        next unless source.line?

        assert_kind_of(LineShrieker, source.line)
      end
    end

    def test_piefed
      Source.all do |source|
        assert_boolean(source.piefed?)
        next unless source.piefed?

        assert_kind_of(PiefedShrieker, source.piefed)
      end
    end

    def test_shriekers
      Source.all do |source|
        source.shriekers do |shrieker|
          assert_kind_of([MastodonShrieker, MisskeyShrieker, WebhookShrieker, LineShrieker, PiefedShrieker, NostrShrieker], shrieker)
        end
      end
    end

    def test_mulukhiya
      Source.all do |source|
        next unless source.mulukhiya

        assert_kind_of(MulukhiyaService, source.mulukhiya)
      end
    end

    def test_remote_tagging?
      Source.all do |source|
        assert_boolean(source.remote_tagging?)
      end
    end

    def test_tags
      Source.all do |source|
        source.tags.each do |tag|
          assert_kind_of(String, tag)
        end
      end
    end

    def test_visibility
      Source.all do |source|
        assert_kind_of(String, source.visibility)
      end
    end

    def test_prefix
      Source.all.select(&:prefix).each do |source|
        assert_kind_of(String, source.prefix)
      end
    end

    def test_post_at
      Source.all.select(&:post_at).each do |source|
        assert_kind_of(String, source.post_at)
        assert_kind_of(String, source.at)
        assert_predicate(Rufus::Scheduler.parse(source.post_at), :present?)
      end
    end

    def test_cron
      Source.all.select(&:cron).each do |source|
        assert_kind_of(String, source.cron)
        assert_predicate(Rufus::Scheduler.parse(source.cron), :present?)
      end
    end

    def test_period
      Source.all.select(&:period).each do |source|
        assert_kind_of(String, source.period)
        assert_kind_of(String, source.every)
        assert_predicate(Rufus::Scheduler.parse(source.every), :present?)
      end
    end

    def test_monitored?
      Source.all.each do |source|
        assert_boolean(source.monitored?)
        # #1503: 無効ソースは scheduler に register されないので監視もしない
        assert_equal(!source.disable? && source.post_at.nil?, source.monitored?)
      end
    end

    def test_next_run_at
      now = Time.now
      Source.all.each do |source|
        next_run = source.next_run_at(now)
        if source.post_at
          assert_nil(next_run)
        else
          assert_kind_of(Time, next_run)
          assert_operator(next_run, :>, now)
        end
      end
    end

    def test_monitor_grace_seconds
      Source.all.each do |source|
        grace = source.monitor_grace_seconds
        if source.post_at
          assert_nil(grace)
        else
          assert_kind_of(Integer, grace)
          assert_operator(grace, :>, 0)
        end
      end
    end

    # #1456: 配信エラーは渡された collector へ集約され、別インスタンス経由でも記録される。
    def test_shriek_collects_delivery_errors
      saved = ENV.fetch('TEST', nil)
      ENV.delete('TEST') # Environment.test? を false にし shrieker を実際に走らせる
      # ⚠ 設定も読み直す。`TEST` だけ外すと `test/sources/` がメモリに残り、
      # 「テストではない実行」の前提が半分しか成り立たない（ensure の後は teardown が戻す）。
      config.reload
      shrieker = Object.new
      def shrieker.exec(_params)
        raise('simulated delivery failure')
      end
      source = Source.new({'id' => 'test-delivery-collect'})
      source.define_singleton_method(:shriekers) do |&block|
        next enum_for(:shriekers) unless block
        block.call(shrieker)
      end
      stats = DeliveryStats.new
      source.shriek(template: nil, visibility: nil, stats:)

      assert_equal(1, stats.error_count)
      assert_equal(1, stats.attempted_count)
      assert_equal(0, stats.delivered_count)
      assert_kind_of(RuntimeError, stats.first_error)
      assert_nothing_raised do
        source.shriek(template: nil, visibility: nil, stats: nil)
      end
      assert_equal(1, stats.error_count)
    ensure
      ENV['TEST'] = saved
    end

    # 🔴 **#1484: Template は Shrieker ごとに複製して渡す。**
    #
    # ⚠ 各 Shrieker は描画の前に `[:tag]` を書き換える。同じ Template を渡すと、
    # 前の Shrieker（Line は false を立てる）のフラグが、自分では立てない Shrieker に見える。
    def test_shriek_isolates_template_per_shrieker
      saved = ENV.fetch('TEST', nil)
      ENV.delete('TEST')
      config.reload
      seen = []
      writer = Object.new
      writer.define_singleton_method(:exec) {|body| body[:template][:tag] = false}
      reader = Object.new
      reader.define_singleton_method(:exec) {|body| seen.push(body[:template][:tag])}
      source = Source.new({'id' => 'test-template-isolation'})
      source.define_singleton_method(:shriekers) do |&block|
        next enum_for(:shriekers) unless block
        [writer, reader].each {|v| block.call(v)}
      end
      template = Template.new('common')
      source.shriek(template:, visibility: nil, stats: DeliveryStats.new)

      assert_equal([nil], seen, '前の Shrieker が立てたフラグが見えている')
      assert_nil(template[:tag], '呼び出し側の Template が書き換わっている')
    ensure
      ENV['TEST'] = saved
    end

    # #1433: 成功した配信も計上される。
    def test_shriek_counts_deliveries
      saved = ENV.fetch('TEST', nil)
      ENV.delete('TEST')
      config.reload
      shrieker = Object.new
      def shrieker.exec(_params)
        # 何もせず成功する shrieker
      end
      source = Source.new({'id' => 'test-delivery-count'})
      source.define_singleton_method(:shriekers) do |&block|
        next enum_for(:shriekers) unless block
        block.call(shrieker)
      end
      stats = DeliveryStats.new
      source.shriek(template: nil, visibility: nil, stats:)

      assert_equal(1, stats.attempted_count)
      assert_equal(1, stats.delivered_count)
      assert_false(stats.error?)
      assert_false(stats.noop?)
    ensure
      ENV['TEST'] = saved
    end

    # #1504: 設定されているのに組み立てられなかった宛先を「未達」として計上する。
    # 🔴 アクセサが例外を握って nil を返すと宛先が shriekers から消えるため、
    # 計上しないと attempted=0 の no-op success になり、投稿できていないのに緑になる。
    # url にスキームが無いので MastodonShrieker の生成が必ず失敗する（通信は起きない）。
    def test_shriek_records_unavailable_dest
      source = Source.new({
        'id' => 'test-dest-unavailable',
        'dest' => {'mastodon' => {'url' => 'mastodon.example.com', 'token' => 'x'}},
      })

      assert_equal(1, source.dest_count)
      assert_equal(0, source.shriekers.to_a.size)

      stats = DeliveryStats.new
      delivered = source.shriek(template: nil, visibility: nil, stats:)

      assert_equal(0, delivered)
      assert_equal(1, stats.attempted_count)
      assert_equal(0, stats.delivered_count)
      assert_equal({'UnavailableDest' => 1}, stats.shrieker_errors)
      assert_true(stats.error?)
    end

    # 宛先が全部組み立てられたときは計上しない（過検知しない）。
    def test_shriek_does_not_record_available_dest
      source = Source.new({'id' => 'test-dest-available'})
      shrieker = Object.new
      def shrieker.exec(_params)
      end
      source.define_singleton_method(:shriekers) do |&block|
        next enum_for(:shriekers) unless block
        block.call(shrieker)
      end
      source.define_singleton_method(:dest_count) {1}

      stats = DeliveryStats.new
      source.shriek(template: nil, visibility: nil, stats:)

      assert_equal({}, stats.shrieker_errors)
      assert_false(stats.error?)
    end

    # #1470: silence_tolerance は未指定なら検知しない (opt-in)。
    def test_monitor_silence_tolerance_seconds
      assert_nil(Source.new({'id' => 'test-silence-unset'}).monitor_silence_tolerance_seconds)
      source = Source.new({'id' => 'test-silence-str', 'monitor' => {'silence_tolerance' => '1d'}})

      assert_equal(86_400, source.monitor_silence_tolerance_seconds)
      source = Source.new({'id' => 'test-silence-int', 'monitor' => {'silence_tolerance' => 600}})

      assert_equal(600, source.monitor_silence_tolerance_seconds)
    end

    # #1558: error_streak_threshold は未指定ならグローバル値へ倒す。
    # ⚠ silence_tolerance と違い opt-out ではなく「既定つきの上書き」。
    def test_monitor_error_streak_threshold
      global = Config.instance['/monitor/error_streak_threshold']

      assert_equal(global, Source.new({'id' => 'test-streak-unset'}).monitor_error_streak_threshold)
      source = Source.new({'id' => 'test-streak-set', 'monitor' => {'error_streak_threshold' => 4}})

      assert_equal(4, source.monitor_error_streak_threshold)
    end

    # ⚠ 0 や負値は「1 回も失敗していなくても赤」になるだけなので既定へ倒す。
    # スキーマ (minimum: 1) を通らない値だが、スキーマは load 時に当たらない
    # （source edit / source validate だけ）ので実行時に来うる。
    def test_monitor_error_streak_threshold_rejects_non_positive
      global = Config.instance['/monitor/error_streak_threshold']
      # ⚠ 文字列は受けない。silence_tolerance は Rufus の duration を受けるので
      # 書き方が非対称だが、回数に単位は無いので整数だけに絞る
      ['4', '3d', true].each do |value|
        source = Source.new({'id' => 'test-streak-str', 'monitor' => {'error_streak_threshold' => value}})

        assert_equal(global, source.monitor_error_streak_threshold, "value=#{value.inspect}")
      end
      [0, -1].each do |value|
        source = Source.new({'id' => 'test-streak-bad', 'monitor' => {'error_streak_threshold' => value}})

        assert_equal(global, source.monitor_error_streak_threshold, "value=#{value}")
      end
    end

    SILENT_ID = '__test_source_silent__'.freeze

    def silent_source(extra = {})
      SourceRunLog.where(source_id: SILENT_ID).delete
      return Source.new({'id' => SILENT_ID}.merge(extra))
    end

    def record_run(at:, delivered_count: 0)
      SourceRunLog.create({
        source_id: SILENT_ID,
        executed_at: at,
        status: SourceRunLog::STATUS_SUCCESS,
        duration_ms: 100,
        attempted_count: delivered_count,
        delivered_count:,
      })
    end

    def test_silent?
      # しきい値未指定なら常に false
      source = silent_source
      record_run(at: Time.now - 86_400_000, delivered_count: 1)

      assert_false(source.silent?)

      # run_log がまったく無ければ観測開始時刻も出せないので断定しない
      source = silent_source({'monitor' => {'silence_tolerance' => '1d'}})

      assert_false(source.silent?)

      # しきい値を超えて配信が途絶えていれば true
      source = silent_source({'monitor' => {'silence_tolerance' => '1d'}})
      record_run(at: Time.now - 172_800, delivered_count: 1)
      record_run(at: Time.now)

      assert_true(source.silent?)

      # しきい値内なら false
      source = silent_source({'monitor' => {'silence_tolerance' => '1d'}})
      record_run(at: Time.now - 60, delivered_count: 1)

      assert_false(source.silent?)
    ensure
      SourceRunLog.where(source_id: SILENT_ID).delete
    end

    # #1483: 一度も配信していないソースは、観測を始めてからの経過を下限として使う。
    # ここを「実績が無いので断定しない」にすると、開設以来ずっと壊れているソースだけが
    # 恒久的に検知対象外になる。
    def test_silent_never_delivered
      source = silent_source({'monitor' => {'silence_tolerance' => '1d'}})
      record_run(at: Time.now - 172_800)
      record_run(at: Time.now)

      assert_true(source.silent?)

      # 🔴 観測を始めたばかりなら「まだ判定できない」＝ nil (#1502)。
      # ⚠ ここを false にすると「健全」と区別がつかない。
      source = silent_source({'monitor' => {'silence_tolerance' => '1d'}})
      record_run(at: Time.now - 60)

      assert_nil(source.silent?, '「健全」と「判定不能」を兼ねている')
    ensure
      SourceRunLog.where(source_id: SILENT_ID).delete
    end

    # 🔴 **`silent: false` が「健全」と「判定不能」を兼ねていないこと (#1502)。**
    # #1483 で fallback を捨てて observed_since 起点にした結果、run_log 上に配信実績が
    # 無いソースは「観測開始から tolerance 経過するまで」検知されない。本番実測では
    # `precure-toei-event`（180d）の検知が 2027-01-30 まで後ろ倒しになる。
    # ⚠ 検知しないこと自体は #1483 の判断どおりで変えない。**嘘をつかないようにする。**
    def test_silent_states
      # 配信実績があってしきい値内 ＝ 健全
      source = silent_source({'monitor' => {'silence_tolerance' => '1d'}})
      record_run(at: Time.now - 60, delivered_count: 1)

      assert_false(source.silent?)
      assert_equal(Source::BASELINE_DELIVERY, source.silence_baseline_origin)

      # 配信実績が無く観測も浅い ＝ 判定不能
      source = silent_source({'monitor' => {'silence_tolerance' => '1d'}})
      record_run(at: Time.now - 60)

      assert_nil(source.silent?)
      assert_equal(Source::BASELINE_OBSERVATION, source.silence_baseline_origin)

      # しきい値未設定は「この機能を使っていない」＝判定不能ではない
      source = silent_source
      record_run(at: Time.now - 60)

      assert_false(source.silent?)
    ensure
      SourceRunLog.where(source_id: SILENT_ID).delete
    end

    # ⚠ 運用者が確認したら判定不能ではなくなる。起点も `acknowledgement` に変わるので、
    # 「なぜ緑なのか」が外から読める (#1505)。
    def test_silence_baseline_origin_after_acknowledge
      source = silent_source({'monitor' => {'silence_tolerance' => '1d'}})
      record_run(at: Time.now - 60)
      SilenceAck.acknowledge(SILENT_ID)

      assert_false(source.silent?)
      assert_equal(Source::BASELINE_ACKNOWLEDGEMENT, source.silence_baseline_origin)
    ensure
      SourceRunLog.where(source_id: SILENT_ID).delete
      SilenceAck.where(source_id: SILENT_ID).delete
    end

    # ⚠ 初回 run でいきなり配信できたソースは、observed_since と同じ行なので時刻が
    # 一致する。`observation` ではなく `delivery` になること。
    def test_silence_baseline_origin_prefers_delivery_on_tie
      source = silent_source({'monitor' => {'silence_tolerance' => '1d'}})
      record_run(at: Time.now - 60, delivered_count: 1)

      assert_equal(Source::BASELINE_DELIVERY, source.silence_baseline_origin)
    ensure
      SourceRunLog.where(source_id: SILENT_ID).delete
    end

    # #1482: run を error に倒すのは 1 件も配信できなかったときだけ。
    # 部分失敗まで error にすると、エントリ 1 件の失敗で日次 cron のソースが
    # 次の run まで healthz 503 に貼り付く。
    def test_finalize_run_log_status
      assert_equal(SourceRunLog::STATUS_SUCCESS, finalize_run(delivered: 3, errored: 0).status)
      assert_equal(SourceRunLog::STATUS_PARTIAL, finalize_run(delivered: 99, errored: 1).status)
      assert_equal(SourceRunLog::STATUS_ERROR, finalize_run(delivered: 0, errored: 3).status)
      # 全滅だけが error_streak を立てる
      assert_equal(1, SourceRunLog.error_streak(SILENT_ID))
    ensure
      SourceRunLog.where(source_id: SILENT_ID).delete
    end

    # 部分失敗でも失敗の内訳は残す
    def test_finalize_run_log_partial_keeps_errors
      log = finalize_run(delivered: 99, errored: 1)

      assert_equal(100, log.attempted_count)
      assert_equal(99, log.delivered_count)
      assert_not_nil(log.error_message)
      assert_equal({'TomatoShrieker::MastodonShrieker' => 1}, log.shrieker_error_counts)
    ensure
      SourceRunLog.where(source_id: SILENT_ID).delete
    end

    def finalize_run(delivered:, errored:)
      SourceRunLog.where(source_id: SILENT_ID).delete
      source = Source.new({'id' => SILENT_ID})
      stats = DeliveryStats.new
      delivered.times {stats.record_success(MastodonShrieker.allocate)}
      errored.times {stats.record_error(MastodonShrieker.allocate, RuntimeError.new('boom'))}
      source.instance_variable_set(:@delivery_stats, stats)
      source.send(:finalize_run_log, Time.now)
      return SourceRunLog.latest_for(SILENT_ID)
    end

    # #1483: entry.published 由来の fallback は配信の成否と無関係に前進するので、
    # silent? の判定には使わない。表示用には残っている。
    def test_silent_ignores_fallback
      source = silent_source({'monitor' => {'silence_tolerance' => '1d'}})
      source.define_singleton_method(:last_delivered_at_fallback) {Time.now}
      record_run(at: Time.now - 172_800, delivered_count: 1)

      assert_equal('run_log', source.last_delivered_at_origin)
      assert_true(source.silent?)
    ensure
      SourceRunLog.where(source_id: SILENT_ID).delete
    end

    # ⚠ #1502 で 3 値になった。`nil`（判定不能）も正当な返り値。
    def test_silent_tri_state
      Source.all do |source|
        assert_include([true, false, nil], source.silent?)
      end
    end

    def test_classes
      Source.classes.each do |source_class|
        assert_kind_of(Class, source_class[:class])
        assert_kind_of(String, source_class[:config])
      end
    end

    def test_create_tags
      source = TextSource.new('source' => {'text' => 'dummy'}, 'dest' => {'tags' => ['precure_fun']})
      tags = source.create_tags('dummy')

      assert_kind_of(Set, tags)
      assert_equal(Set['#precure_fun'], tags)
    end

    def test_create_tags_with_short_tag
      # 2文字以下のタグも素通しする (短タグフィルタはモロヘイヤ側責務)
      source = TextSource.new('source' => {'text' => 'dummy'}, 'dest' => {'tags' => ['実況', 'precure_fun']})

      assert_nothing_raised do
        tags = source.create_tags('dummy')

        assert_equal(Set['#実況', '#precure_fun'], tags)
      end
    end

    private

    def retry_source(retry_params, &)
      params = {
        'id' => RETRY_ID,
        'source' => {'text' => 'body'},
        'schedule' => {'cron' => '1 0 * * *'},
        'dest' => {'hooks' => ['https://hook.example.test/retry']},
      }
      params['schedule']['retry'] = retry_params if retry_params
      source = TextSource.new(params)
      source.define_singleton_method(:exec, &)
      return source
    end

    def retry_jobs
      return Scheduler.instance.scheduler.jobs(tag: RETRY_ID)
    end

    def cleanup_retry
      retry_jobs.each(&:unschedule)
      SourceRunLog.where(source_id: RETRY_ID).delete
    end
  end
end
