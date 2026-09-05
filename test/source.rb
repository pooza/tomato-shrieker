module TomatoShrieker
  class SourceTest < TestCase
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

    # #1433: 成功した配信も計上される。
    def test_shriek_counts_deliveries
      saved = ENV.fetch('TEST', nil)
      ENV.delete('TEST')
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
      assert_equal('delivery', source.silence_baseline_origin)

      # 配信実績が無く観測も浅い ＝ 判定不能
      source = silent_source({'monitor' => {'silence_tolerance' => '1d'}})
      record_run(at: Time.now - 60)

      assert_nil(source.silent?)
      assert_equal('observation', source.silence_baseline_origin)

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
      assert_equal('acknowledgement', source.silence_baseline_origin)
    ensure
      SourceRunLog.where(source_id: SILENT_ID).delete
      SilenceAck.where(source_id: SILENT_ID).delete
    end

    # ⚠ 初回 run でいきなり配信できたソースは、observed_since と同じ行なので時刻が
    # 一致する。`observation` ではなく `delivery` になること。
    def test_silence_baseline_origin_prefers_delivery_on_tie
      source = silent_source({'monitor' => {'silence_tolerance' => '1d'}})
      record_run(at: Time.now - 60, delivered_count: 1)

      assert_equal('delivery', source.silence_baseline_origin)
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
  end
end
