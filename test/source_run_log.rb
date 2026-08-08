module TomatoShrieker
  class SourceRunLogTest < TestCase
    SOURCE_ID = '__test_source_run_log__'.freeze

    def setup
      cleanup
      @base = Time.now - 3600
    end

    def teardown
      cleanup
      super
    end

    def cleanup
      SourceRunLog.where(source_id: SOURCE_ID).delete
    end

    # 新しい順に並べたい run を、古い順に積む
    def create_logs(*specs)
      specs.each_with_index do |spec, i|
        SourceRunLog.create({
          source_id: SOURCE_ID,
          executed_at: @base + (i * 60),
          status: spec[:status] || SourceRunLog::STATUS_SUCCESS,
          duration_ms: spec[:duration_ms] || 100,
          attempted_count: spec[:attempted_count] || 0,
          delivered_count: spec[:delivered_count] || 0,
          shrieker_errors: spec[:shrieker_errors],
        })
      end
    end

    def test_noop?
      create_logs(
        {status: SourceRunLog::STATUS_SUCCESS, attempted_count: 0},
        {status: SourceRunLog::STATUS_SUCCESS, attempted_count: 1, delivered_count: 1},
        {status: SourceRunLog::STATUS_ERROR, attempted_count: 0},
      )
      logs = SourceRunLog.recent_for(SOURCE_ID, 10).reverse

      assert_true(logs[0].noop?)
      assert_false(logs[1].noop?)
      # run 自体が落ちた場合は試行ゼロでも no-op ではない
      assert_false(logs[2].noop?)
    end

    # #1457: no-op run は「run が完走した」証拠なので streak を切る。
    # ここを読み飛ばすと、新着の少ないソースが一過性エラー 1 回で 503 に貼り付く。
    def test_error_streak_broken_by_noop
      create_logs(
        {status: SourceRunLog::STATUS_SUCCESS, attempted_count: 1, delivered_count: 1},
        {status: SourceRunLog::STATUS_ERROR, attempted_count: 1},
        {status: SourceRunLog::STATUS_SUCCESS, attempted_count: 0},
      )

      assert_equal(0, SourceRunLog.error_streak(SOURCE_ID))
    end

    def test_error_streak_counts_consecutive_errors
      create_logs(
        {status: SourceRunLog::STATUS_SUCCESS, attempted_count: 1, delivered_count: 1},
        {status: SourceRunLog::STATUS_ERROR, attempted_count: 1},
        {status: SourceRunLog::STATUS_ERROR, attempted_count: 1},
      )

      assert_equal(2, SourceRunLog.error_streak(SOURCE_ID))
    end

    # migration 010 直後は既存行が attempted_count = 0 で backfill される。
    # ここで過去のエラーが生き返ると、デプロイ直後に健全なソースが一斉 503 になる。
    def test_error_streak_after_migration_backfill
      logs = Array.new(20) {|i| {status: i == 5 ? SourceRunLog::STATUS_ERROR : SourceRunLog::STATUS_SUCCESS, attempted_count: 0}}
      create_logs(*logs)

      assert_equal(0, SourceRunLog.error_streak(SOURCE_ID))
    end

    # 配信できた success が来たら streak は切れる
    def test_error_streak_reset_by_delivery
      create_logs(
        {status: SourceRunLog::STATUS_ERROR, attempted_count: 1},
        {status: SourceRunLog::STATUS_SUCCESS, attempted_count: 1, delivered_count: 1},
      )

      assert_equal(0, SourceRunLog.error_streak(SOURCE_ID))
    end

    # #1470: retention_days を超えて沈黙しても、根拠行が残って検知が続く。
    # 刈ってしまうと沈黙が長引くほど検知できなくなる。
    def test_prune_keeps_last_delivered_row
      SourceRunLog.create(
        source_id: SOURCE_ID, executed_at: Time.now - (20 * 86_400),
        status: SourceRunLog::STATUS_SUCCESS, duration_ms: 10,
        attempted_count: 1, delivered_count: 1
      )
      SourceRunLog.create(
        source_id: SOURCE_ID, executed_at: Time.now - (19 * 86_400),
        status: SourceRunLog::STATUS_SUCCESS, duration_ms: 10,
        attempted_count: 0, delivered_count: 0
      )
      SourceRunLog.prune(14)
      remain = SourceRunLog.where(source_id: SOURCE_ID).all

      assert_equal(1, remain.size)
      assert_true(remain.first.delivered?)
      assert_not_nil(SourceRunLog.last_delivered_at(SOURCE_ID))
    end

    # #1483: 未配信のソースは last_delivered_ids に引っかからないので、
    # 最古行を守らないと observed_since が retention_days 前に張り付く。
    def test_prune_keeps_first_run_row
      SourceRunLog.create(
        source_id: SOURCE_ID, executed_at: Time.now - (60 * 86_400),
        status: SourceRunLog::STATUS_SUCCESS, duration_ms: 10,
        attempted_count: 0, delivered_count: 0
      )
      SourceRunLog.create(
        source_id: SOURCE_ID, executed_at: Time.now - (19 * 86_400),
        status: SourceRunLog::STATUS_SUCCESS, duration_ms: 10,
        attempted_count: 0, delivered_count: 0
      )
      SourceRunLog.prune(14)
      remain = SourceRunLog.where(source_id: SOURCE_ID).all

      assert_equal(1, remain.size)
      assert_equal((Time.now - (60 * 86_400)).to_i, SourceRunLog.observed_since(SOURCE_ID).to_i)
    end

    def test_observed_since
      assert_nil(SourceRunLog.observed_since(SOURCE_ID))
      create_logs({attempted_count: 0}, {attempted_count: 1, delivered_count: 1})

      assert_equal(@base.to_i, SourceRunLog.observed_since(SOURCE_ID).to_i)
    end

    # #1482: 配信できたものと失敗したものが混在した run は error と分けて記録し、
    # error_streak を倒さない
    def test_record_partial
      SourceRunLog.record_partial(
        SOURCE_ID, started_at: @base, error: RuntimeError.new('boom'),
        stats: nil
      )
      log = SourceRunLog.latest_for(SOURCE_ID)

      assert_true(log.partial?)
      assert_false(log.error?)
      assert_false(log.noop?)
      assert_equal('RuntimeError: boom', log.error_message)
      assert_equal(0, SourceRunLog.error_streak(SOURCE_ID))
    end

    def test_error_streak_broken_by_partial
      create_logs(
        {status: SourceRunLog::STATUS_ERROR, attempted_count: 1},
        {status: SourceRunLog::STATUS_PARTIAL, attempted_count: 2, delivered_count: 1},
      )

      assert_equal(0, SourceRunLog.error_streak(SOURCE_ID))
    end

    def test_error_streak_empty
      assert_equal(0, SourceRunLog.error_streak(SOURCE_ID))
    end

    # Codex P2: error_streak_threshold が sample_size より大きいと、読む行数が
    # 足りずしきい値に到達し得なくなる（＝何回連続で失敗しても健全のまま）
    def test_streak_window_covers_threshold
      threshold = Config.instance['/monitor/error_streak_threshold']

      assert_operator(SourceRunLog.streak_window, :>=, threshold)
      assert_operator(SourceRunLog.streak_window, :>=, SourceRunLog.sample_size)
    end

    # #1470: 配信ゼロが続いた回数。エラー run も数に入れる
    def test_noop_streak
      create_logs(
        {status: SourceRunLog::STATUS_SUCCESS, attempted_count: 1, delivered_count: 1},
        {status: SourceRunLog::STATUS_SUCCESS, attempted_count: 0},
        {status: SourceRunLog::STATUS_ERROR, attempted_count: 1},
        {status: SourceRunLog::STATUS_SUCCESS, attempted_count: 0},
      )

      assert_equal(3, SourceRunLog.noop_streak(SOURCE_ID))
    end

    def test_last_delivered_at
      assert_nil(SourceRunLog.last_delivered_at(SOURCE_ID))
      create_logs(
        {delivered_count: 1, attempted_count: 1},
        {delivered_count: 0, attempted_count: 0},
      )

      assert_equal(@base.to_i, SourceRunLog.last_delivered_at(SOURCE_ID).to_i)
    end

    def test_duration_stats
      assert_nil(SourceRunLog.duration_stats(SOURCE_ID))
      create_logs(
        {duration_ms: 100},
        {duration_ms: 200},
        {duration_ms: 300},
        {duration_ms: 400},
      )
      stats = SourceRunLog.duration_stats(SOURCE_ID)

      assert_equal(100, stats[:min])
      assert_equal(400, stats[:max])
      assert_equal(250, stats[:avg])
      assert_equal(400, stats[:p95])
    end

    def test_percentile_index
      assert_equal(0, SourceRunLog.percentile_index(1, 95))
      assert_equal(18, SourceRunLog.percentile_index(20, 95))
      assert_equal(94, SourceRunLog.percentile_index(100, 95))
    end

    def test_shrieker_error_distribution
      assert_equal({}, SourceRunLog.shrieker_error_distribution(SOURCE_ID))
      create_logs(
        {status: SourceRunLog::STATUS_ERROR, attempted_count: 2,
         shrieker_errors: JSON.dump('MastodonShrieker' => 1, 'PiefedShrieker' => 1)},
        {status: SourceRunLog::STATUS_ERROR, attempted_count: 1,
         shrieker_errors: JSON.dump('MastodonShrieker' => 2)},
      )
      distribution = SourceRunLog.shrieker_error_distribution(SOURCE_ID)

      assert_equal(3, distribution['MastodonShrieker'])
      assert_equal(1, distribution['PiefedShrieker'])
    end

    def test_shrieker_error_counts_broken_json
      create_logs({shrieker_errors: 'not json'})

      assert_equal({}, SourceRunLog.recent_for(SOURCE_ID, 1).first.shrieker_error_counts)
    end

    def test_error_rate
      assert_nil(SourceRunLog.error_rate(SOURCE_ID))
      create_logs(
        {status: SourceRunLog::STATUS_ERROR, attempted_count: 1},
        {status: SourceRunLog::STATUS_SUCCESS, attempted_count: 1, delivered_count: 1},
        {status: SourceRunLog::STATUS_SUCCESS, attempted_count: 1, delivered_count: 1},
        {status: SourceRunLog::STATUS_SUCCESS, attempted_count: 1, delivered_count: 1},
      )

      assert_in_delta(0.25, SourceRunLog.error_rate(SOURCE_ID))
    end

    def test_summary_for
      create_logs(
        {status: SourceRunLog::STATUS_SUCCESS, attempted_count: 1, delivered_count: 1},
        {status: SourceRunLog::STATUS_ERROR, attempted_count: 1,
         shrieker_errors: JSON.dump('MastodonShrieker' => 1)},
      )
      summary = SourceRunLog.summary_for(SOURCE_ID)

      assert_equal(1, summary[:error_streak])
      assert_equal(1, summary[:noop_streak])
      assert_equal(1, summary[:shrieker_errors]['MastodonShrieker'])
      assert_kind_of(Hash, summary[:duration_ms])
    end

    def test_record_success_with_stats
      stats = DeliveryStats.new
      stats.record_success(MastodonShrieker.allocate)
      SourceRunLog.record_success(SOURCE_ID, started_at: Time.now, stats:)
      log = SourceRunLog.latest_for(SOURCE_ID)

      assert_equal(1, log.attempted_count)
      assert_equal(1, log.delivered_count)
      assert_nil(log.shrieker_errors)
    end

    def test_record_error_with_stats
      stats = DeliveryStats.new
      stats.record_error(MastodonShrieker.allocate, RuntimeError.new('boom'))
      SourceRunLog.record_error(
        SOURCE_ID, started_at: Time.now, error: RuntimeError.new('boom'), stats:
      )
      log = SourceRunLog.latest_for(SOURCE_ID)

      assert_equal(1, log.attempted_count)
      assert_equal(0, log.delivered_count)
      assert_equal({'TomatoShrieker::MastodonShrieker' => 1}, log.shrieker_error_counts)
    end

    # stats を渡さない旧来の呼び出しでも既定値で記録できる
    def test_record_without_stats
      SourceRunLog.record_success(SOURCE_ID, started_at: Time.now)
      log = SourceRunLog.latest_for(SOURCE_ID)

      assert_equal(0, log.attempted_count)
      assert_equal(0, log.delivered_count)
      assert_true(log.noop?)
    end
  end
end
