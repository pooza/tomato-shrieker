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

    # 🔴 **#1608: prune が守る古い行をまたいで数えない。**
    #
    # ⚠⚠ `prune` はソースごとに `first_run_ids` / `last_attempted_ids` /
    # `last_delivered_ids` の 3 行を**無期限に守る**。**疎なソース**では retention 内の
    # 行が `limit` より少ないので、**守られた古い行がそのまま末尾に並ぶ**。間にあった
    # 成功行は消えているので、**何か月も前の最初の run のエラーが直近のエラーと
    # 地続きに見え、streak が水増しされる**＝ 実際には連続していない失敗で
    # `/healthz/source/:id` が 503 を立てる。
    def test_error_streak_stops_at_retention_cutoff
      # 最初の run（error）。⚠ first_run_ids が守るので prune で消えない
      SourceRunLog.create(
        source_id: SOURCE_ID, executed_at: Time.now - (90 * 86_400),
        status: SourceRunLog::STATUS_ERROR, duration_ms: 10,
        attempted_count: 1, delivered_count: 0
      )
      # ⚠ retention の外の success。**prune で消える**＝ streak を切る材料が無くなる
      SourceRunLog.create(
        source_id: SOURCE_ID, executed_at: Time.now - (30 * 86_400),
        status: SourceRunLog::STATUS_SUCCESS, duration_ms: 10,
        attempted_count: 0, delivered_count: 0
      )
      # retention 内の連続エラー 2 件
      [2, 1].each do |days|
        SourceRunLog.create(
          source_id: SOURCE_ID, executed_at: Time.now - (days * 86_400),
          status: SourceRunLog::STATUS_ERROR, duration_ms: 10,
          attempted_count: 1, delivered_count: 0
        )
      end
      SourceRunLog.prune(14)
      remain = SourceRunLog.where(source_id: SOURCE_ID).all

      assert_equal(3, remain.size, '最初の run が保護行として残っている')
      assert_equal(2, SourceRunLog.error_streak(SOURCE_ID), '保護行をまたいで数えない')
    end

    # ⚠ cutoff は**境界の外だけ**を落とす。retention 内の行は今までどおり数える
    # （#1608 で streak が過小になっては意味がない）。
    def test_error_streak_counts_whole_retention_window
      [13, 12, 11].each do |days|
        SourceRunLog.create(
          source_id: SOURCE_ID, executed_at: Time.now - (days * 86_400),
          status: SourceRunLog::STATUS_ERROR, duration_ms: 10,
          attempted_count: 1, delivered_count: 0
        )
      end

      assert_equal(3, SourceRunLog.error_streak(SOURCE_ID))
    end

    # 🔴🔴 **#1586: 段は run_log 自身が持つ。**
    #
    # ⚠⚠ `shrieker_errors` が空でも、エントリ処理段まで進んでいれば緩和を効かせない。
    # **これが CommandSource / IcalendarSource の形**（`create_template` で落ちると
    # `@delivery_stats` は空のまま `exec_with_run_log` の rescue に入る）。
    def test_entry_stage_persisted_from_stats
      stats = DeliveryStats.new
      stats.enter_entry_stage!
      SourceRunLog.record_error(
        SOURCE_ID, started_at: Time.now, error: RuntimeError.new('template broken'), stats:
      )
      log = SourceRunLog.latest_for(SOURCE_ID)

      assert_true(log.entry_stage)
      assert_true(log.entry_stage_error?)
      assert_empty(log.shrieker_error_counts, '代理（shrieker_errors）では捕まらない形')
      assert_true(SourceRunLog.entry_level_error?([log]))
    end

    # ⚠ 取得段で落ちた run は緩和が効いてよい側。
    def test_entry_stage_false_when_fetch_failed
      stats = DeliveryStats.new
      SourceRunLog.record_error(
        SOURCE_ID, started_at: Time.now, error: RuntimeError.new('Bad response 404'), stats:
      )
      log = SourceRunLog.latest_for(SOURCE_ID)

      assert_false(log.entry_stage)
      assert_false(log.entry_stage_error?)
      assert_false(SourceRunLog.entry_level_error?([log]))
    end

    # 🔴 **migration 013 より前の行は `entry_stage` が NULL。**
    # ⚠⚠ ここを「NULL ＝ エントリ処理段」にすると、**デプロイ直後に緩和を掛けている
    # ソースが一斉に 503** になる（migration 010 の backfill で踏んだのと同じ型）。
    # 旧行は従来の代理（`shrieker_errors` の有無）へ倒す。
    def test_entry_stage_null_falls_back_to_shrieker_errors
      create_logs(
        {status: SourceRunLog::STATUS_ERROR, shrieker_errors: JSON.dump({'source#fetch' => 1})},
      )
      log = SourceRunLog.latest_for(SOURCE_ID)

      assert_nil(log.entry_stage, '旧行を模している')
      assert_true(log.entry_stage_error?)
      assert_true(SourceRunLog.entry_level_error?([log]))
    end

    def test_entry_stage_null_without_shrieker_errors_keeps_threshold
      create_logs({status: SourceRunLog::STATUS_ERROR})
      log = SourceRunLog.latest_for(SOURCE_ID)

      assert_nil(log.entry_stage)
      assert_false(log.entry_stage_error?)
      assert_false(SourceRunLog.entry_level_error?([log]))
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

    # 🔴 #1511: 保護行は retention_days を超えて無期限に残るので、そこに
    # error_message が乗ったままだと「例外メッセージは N 日で消える」という
    # 保持上限が保護行だけ外れる。⚠ 判定に使うのは executed_at /
    # attempted_count / delivered_count だけなので、落としても保護は壊れない。
    def test_prune_redacts_error_message_of_protected_rows
      SourceRunLog.create(
        source_id: SOURCE_ID, executed_at: Time.now - (20 * 86_400),
        status: SourceRunLog::STATUS_PARTIAL, duration_ms: 10,
        attempted_count: 2, delivered_count: 1,
        error_message: 'Ginseng::GatewayError: Invalid feed x (https://example.com/f?access_token=TOKENVALUE)'
      )
      SourceRunLog.prune(14)
      remain = SourceRunLog.where(source_id: SOURCE_ID).all

      assert_equal(1, remain.size, '保護行そのものは残る')
      assert_nil(remain.first.error_message)
      assert_true(SourceRunLog.undelivered?(SOURCE_ID), '取りこぼしの判定は生きている')
    end

    # ⚠ 期限内の行の error_message は消さないこと。消すと直近の失敗理由が
    # 読めなくなる。
    def test_prune_keeps_error_message_within_retention
      SourceRunLog.create(
        source_id: SOURCE_ID, executed_at: Time.now - 3600,
        status: SourceRunLog::STATUS_ERROR, duration_ms: 10,
        attempted_count: 1, delivered_count: 0,
        error_message: 'Ginseng::GatewayError: Bad response 404'
      )
      SourceRunLog.prune(14)

      assert_equal(
        'Ginseng::GatewayError: Bad response 404',
        SourceRunLog.where(source_id: SOURCE_ID).first.error_message,
      )
    end

    # 🔴 #1504: 取りこぼしの根拠行を刈ると、赤くなったソースが retention_days の
    # 経過だけで黙って緑に戻る。「次に配信できたときだけ解除する」が壊れる。
    def test_prune_keeps_last_attempted_row
      SourceRunLog.create(
        source_id: SOURCE_ID, executed_at: Time.now - (20 * 86_400),
        status: SourceRunLog::STATUS_PARTIAL, duration_ms: 10,
        attempted_count: 2, delivered_count: 1
      )
      SourceRunLog.create(
        source_id: SOURCE_ID, executed_at: Time.now - (19 * 86_400),
        status: SourceRunLog::STATUS_SUCCESS, duration_ms: 10,
        attempted_count: 0, delivered_count: 0
      )
      SourceRunLog.prune(14)

      assert_true(SourceRunLog.undelivered?(SOURCE_ID))
    end

    def test_undelivered?
      create_logs(
        {attempted_count: 2, delivered_count: 1, status: SourceRunLog::STATUS_PARTIAL},
        {attempted_count: 0},
      )

      # no-op は判定を持ち越す
      assert_true(SourceRunLog.undelivered?(SOURCE_ID))

      create_logs({attempted_count: 2, delivered_count: 2})

      assert_false(SourceRunLog.undelivered?(SOURCE_ID))
    end

    # 全滅も同じ式で拾う（error_streak と二重管理にしない）
    def test_undelivered_covers_total_failure
      create_logs({attempted_count: 2, delivered_count: 0, status: SourceRunLog::STATUS_ERROR})

      assert_true(SourceRunLog.undelivered?(SOURCE_ID))
    end

    # 一度も配信を試みていなければ未達ではない
    def test_undelivered_ignores_noop_only
      create_logs({attempted_count: 0}, {attempted_count: 0})

      assert_false(SourceRunLog.undelivered?(SOURCE_ID))
      assert_nil(SourceRunLog.last_attempted(SOURCE_ID))
    end

    # #1504: 配信手前で落ちた失敗（宛先に一度も触れていない）を未達にしない。
    # 🔴 ここを未達に数えると、解除が「次に全宛先へ届く run」だけなので、
    # 新着の少ないソースが一過性のエラー 1 回で数週間 503 に貼り付く。
    def test_undelivered_ignores_pre_delivery_failure
      stats = DeliveryStats.new
      stats.record_failure('TomatoShrieker::FeedSource#fetch', RuntimeError.new('boom'))
      SourceRunLog.record(
        SOURCE_ID, started_at: Time.now,
        status: SourceRunLog::STATUS_ERROR, error: stats.first_error, stats:
      )

      assert_false(SourceRunLog.undelivered?(SOURCE_ID))
      assert_true(SourceRunLog.latest_for(SOURCE_ID).error?)
    end

    # #1483: 未配信のソースは last_delivered_ids に引っかからないので、
    # 最古行を守らないと observed_since が retention_days 前に張り付く。
    def test_prune_keeps_first_run_row
      # ⚠ **基準時刻は 1 回だけ取る (#1553)。**挿入時と assert 時で `Time.now` を
      # 別々に呼ぶと、間で秒境界をまたいだときだけ 1 ずれて落ちる。
      # 🔴 再実行で緑になるテストがあると、**本物の回帰まで「たぶんフレーク」で
      # 流される**ようになる。`setup` の `@base` に揃える。
      first = @base - (60 * 86_400)
      SourceRunLog.create(
        source_id: SOURCE_ID, executed_at: first,
        status: SourceRunLog::STATUS_SUCCESS, duration_ms: 10,
        attempted_count: 0, delivered_count: 0
      )
      SourceRunLog.create(
        source_id: SOURCE_ID, executed_at: @base - (19 * 86_400),
        status: SourceRunLog::STATUS_SUCCESS, duration_ms: 10,
        attempted_count: 0, delivered_count: 0
      )
      SourceRunLog.prune(14)
      remain = SourceRunLog.where(source_id: SOURCE_ID).all

      assert_equal(1, remain.size)
      assert_equal(first.to_i, SourceRunLog.observed_since(SOURCE_ID).to_i)
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

    # #1558: しきい値はソース単位で上書きできる。⚠ **窓も一緒に広げないと、
    # しきい値だけ大きくしても到達し得ないまま健全扱いになる。**
    def test_streak_window_covers_source_threshold
      wide = SourceRunLog.sample_size + 10

      assert_operator(SourceRunLog.streak_window(wide), :>=, wide)
      # 小さい上書きで窓を狭めない（sample_size は他の集計も使う）
      assert_equal(SourceRunLog.sample_size, SourceRunLog.streak_window(1))
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

    # #1469: Sequel / SQLite の例外は ASCII-8BIT で上がる。
    # 保存の時点で UTF-8 へ倒しておかないと、監視の JSON 化がそこで壊れる。
    def test_record_error_normalizes_binary_message
      SourceRunLog.record_error(
        SOURCE_ID, started_at: Time.now, error: binary_error('テーブル「台詞」が無い')
      )
      log = SourceRunLog.latest_for(SOURCE_ID)

      assert_equal(Encoding::UTF_8, log.error_message.encoding)
      assert_include(log.error_message, 'テーブル「台詞」が無い')
      # 監視の経路が実際に通ること。json 3.0 ではここが例外になる
      assert_equal(log.error_message, JSON.parse(JSON.dump(v: log.error_message))['v'])
    end

    # 不正バイトは json 2.x でも今すぐ JSON::GeneratorError になる（警告どまりではない）
    def test_record_error_scrubs_invalid_bytes
      SourceRunLog.record_error(
        SOURCE_ID, started_at: Time.now, error: binary_error("boom \xff\xfe end")
      )
      log = SourceRunLog.latest_for(SOURCE_ID)

      assert_equal(Encoding::UTF_8, log.error_message.encoding)
      assert_true(log.error_message.valid_encoding?)
      assert_nothing_raised {JSON.dump(v: log.error_message)}
    end

    # 保存時の正規化より前に書かれた行を読んでも壊れない (#1469)
    def test_error_message_normalizes_legacy_row
      create_logs({status: SourceRunLog::STATUS_ERROR})
      log = SourceRunLog.latest_for(SOURCE_ID)
      log.this.update(error_message: Sequel.blob('RuntimeError: 台詞が無い'))

      assert_equal(Encoding::UTF_8, SourceRunLog.latest_for(SOURCE_ID).error_message.encoding)
      assert_include(SourceRunLog.latest_for(SOURCE_ID).error_message, '台詞が無い')
    end

    def binary_error(message)
      return RuntimeError.new(message.dup.force_encoding(Encoding::ASCII_8BIT))
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
