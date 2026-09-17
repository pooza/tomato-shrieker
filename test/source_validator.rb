module TomatoShrieker
  class SourceValidatorTest < TestCase
    def test_valid_feed
      assert_empty(SourceValidator.validate(
        'source' => {'feed' => 'https://example.com/feed'},
        'dest' => {'hooks' => ['https://mastodon.example.com/webhook/x'], 'tags' => ['a']},
      ))
    end

    def test_valid_full
      assert_true(SourceValidator.valid?(
        'disable' => true,
        'test' => false,
        'keep' => {'years' => 50},
        'schedule' => {'cron' => '0 0 * * *', 'remind' => {'enable' => true}},
        'source' => {'ical' => 'https://example.com/c.ics'},
        'dest' => {
          'sanitize' => 'html',
          'mastodon' => {'url' => 'https://example.com', 'token' => 't'},
          'tags' => ['a', 'b'],
        },
      ))
    end

    def test_valid_hook_hash
      assert_true(SourceValidator.valid?(
        'source' => {'feed' => 'https://example.com/feed'},
        'dest' => {'hooks' => [{'url' => 'https://example.com/webhook', 'channel' => '#a'}]},
      ))
    end

    # 🔴 **#1570: 起動なら倒れる cron を NG にすること。**
    #
    # ⚠ **これがスキーマを通っていたのが本番事故の入口。**`cron` は `type: string` しか
    # 見ていないので、2026-09-05 に `*` がシェルの glob で展開された 338 文字が
    # そのまま通り、次の起動で `register_all` が倒れて全ソースが 50 秒止まった。
    def test_invalid_cron_is_ng
      errors = SourceValidator.validate(
        'source' => {'feed' => 'https://example.com/feed'},
        'dest' => {'hooks' => ['https://example.com/x']},
        'schedule' => {'cron' => '17,47 CLAUDE.md Gemfile Gemfile.lock README.md'},
      )

      assert_not_empty(errors)
      assert_true(errors.any? {|v| v.start_with?('/schedule/cron:')}, errors.inspect)
    end

    def test_valid_cron_passes
      assert_empty(SourceValidator.schedule_errors('schedule' => {'cron' => '17,47 * * * *'}))
    end

    def test_invalid_every_is_ng
      errors = SourceValidator.schedule_errors('schedule' => {'every' => '5x'})

      assert_true(errors.any? {|v| v.start_with?('/schedule/every:')}, errors.inspect)
    end

    # ⚠ **キーと値の取り違えを見逃さないこと。**総称の `Rufus::Scheduler.parse` は
    # cron 文字列も `Fugit::Cron` として通すので、`every` に cron を書いても素通りする。
    # `register` と同じパーサ（`parse_duration`）で引いていれば弾ける。
    def test_cron_string_in_every_is_ng
      errors = SourceValidator.schedule_errors('schedule' => {'every' => '0 0 * * *'})

      assert_true(errors.any? {|v| v.start_with?('/schedule/every:')}, errors.inspect)
    end

    # 🔴 **4.10.0 リリース前レビュー 赤 C: 頻度 0 の `every` を NG にすること。**
    #
    # ⚠⚠ `parse_duration` は `'0s'` / `'0'` / `'0m'` で例外を投げず 0 を返すだけなので、
    # パースの成否だけを見ると素通りする。`scheduler.every` は
    # `cannot schedule ... with a frequency of 0` で倒れる＝ 2026-09-05 と同じ形の全停止。
    def test_zero_every_is_ng
      ['0s', '0', '0m', '-5m'].each do |value|
        errors = SourceValidator.schedule_errors('schedule' => {'every' => value})

        assert_true(errors.any? {|v| v.start_with?('/schedule/every:')}, "#{value}: #{errors.inspect}")
      end
    end

    # 🔴 **赤 A: 判別キーがどのソースクラスにも一致しない定義を NG にすること。**
    #
    # ⚠ スキーマの `source` は `minProperties: 1` しか見ないので、`keyword` のような
    # 未知のキーも通る。以前の `validate` は WARN どまりで、`register_all` だけが倒れた。
    def test_unmatched_source_is_ng
      sources = [
        {'keyword' => 'プリキュア'},
        {'github' => {'timeline' => 'releases'}},
        {'news' => {}},
        {'feeed' => 'https://example.com/feed'},
      ]
      sources.each do |source|
        errors = SourceValidator.validate(
          'source' => source,
          'dest' => {'hooks' => ['https://example.com/x']},
        )

        assert_true(errors.any? {|v| v.start_with?('/source: no source class matched')},
          "#{source}: #{errors.inspect}")
      end
    end

    # 🔴 **赤 B: 止めた定義は unmatched でも検査しない。**`disable` が唯一の逃げ道。
    def test_disabled_unmatched_source_skips_startup_check
      assert_empty(SourceValidator.startup_errors(
        'disable' => true,
        'source' => {'feeed' => 'https://example.com/feed'},
      ))
    end

    def test_invalid_at_is_ng
      errors = SourceValidator.schedule_errors('schedule' => {'at' => 'not a time'})

      assert_true(errors.any? {|v| v.start_with?('/schedule/at:')}, errors.inspect)
    end

    # 🔴 **止めたソースは検査しない。**`Scheduler#desired_sources` が弾くので起動は
    # 倒れない。**「直せないなら disable すれば通る」が `source reload` の拒否 (#1570)
    # の唯一の逃げ道**なので、ここが厳しいと逃げ道ごと塞ぐ。
    def test_disabled_source_skips_schedule_check
      assert_empty(SourceValidator.schedule_errors(
        'disable' => true,
        'schedule' => {'cron' => 'not a cron'},
      ))
    end

    # 🔴 **#1570 の Codex P2: register が実際に使う 1 本だけを見ること。**
    #
    # ⚠ スキーマは複数キーを許す。`register` は `at` > `cron` > `every` の順で
    # **最初の 1 本しか使わない**ので、`at` が妥当なら壊れた `cron` があっても起動する。
    # ⚠⚠ 全部を見ると**「起動はできるのに reload は拒否される」**＝ #1570 が直した
    # 食い違いを、向きだけ変えて自分で作ることになる。
    def test_ignores_schedule_keys_register_never_uses
      assert_empty(SourceValidator.schedule_errors(
        'schedule' => {'at' => '2099-12-31 00:00', 'cron' => 'not a cron'},
      ))
    end

    # 逆に、実際に使われるほうが壊れていれば拾う。
    def test_reports_the_key_register_actually_uses
      errors = SourceValidator.schedule_errors(
        'schedule' => {'cron' => 'not a cron', 'every' => '5m'},
      )

      assert_true(errors.any? {|v| v.start_with?('/schedule/cron:')}, errors.inspect)
    end

    # 🔴 **#1570 の Codex P1: remind ジョブも起動を倒しうる。**
    #
    # ⚠ `IcalendarSource#register` は `schedule_remind` を**本体より先に**呼ぶ。
    # ⚠⚠ `minutes: 0` は `parse_duration` では通る（0 を返すだけ）が、`every` が
    # `cannot schedule ... with a frequency of 0` で倒れる。
    def test_zero_remind_minutes_is_ng
      errors = SourceValidator.schedule_errors(
        'source' => {'ical' => 'https://example.com/c.ics'},
        'schedule' => {'cron' => '0 0 * * *', 'remind' => {'enable' => true, 'minutes' => 0}},
      )

      assert_true(errors.any? {|v| v.start_with?('/schedule/remind/minutes:')}, errors.inspect)
    end

    # ⚠ **remind ジョブを立てるのは IcalendarSource だけ。**他のソースでは無視される
    # 設定なので、ここで NG にすると「起動はできるのに reload は拒否される」になる。
    def test_remind_ignored_for_sources_that_never_schedule_it
      assert_empty(SourceValidator.schedule_errors(
        'source' => {'feed' => 'https://example.com/feed'},
        'schedule' => {'every' => '5m', 'remind' => {'enable' => true, 'minutes' => 0}},
      ))
    end

    # 省略時の既定 (5 分) は妥当。⚠ ここが IcalendarSource#remind_minutes とずれると
    # 「省略時は倒れないのに明示すると倒れる」（またはその逆）になる。
    def test_default_remind_minutes_passes
      assert_empty(SourceValidator.schedule_errors(
        'source' => {'ical' => 'https://example.com/c.ics'},
        'schedule' => {'cron' => '0 0 * * *', 'remind' => {'enable' => true}},
      ))
    end

    # 📌 **スキーマと「起動が倒れるか」は別の線引き。**`minimum: 1` は authoring の
    # ゲート（`validate` / `add` / `edit`）なので、remind を立てないソースでも NG にする。
    # ⚠ 一方 `schedule_errors`（＝ `reload` の拒否条件）は起動が倒れるものだけ。
    # **validate のほうが厳しい**のは意図どおり。
    def test_schema_rejects_zero_remind_minutes_for_any_source
      assert_false(SourceValidator.valid?(
        'source' => {'feed' => 'https://example.com/feed'},
        'dest' => {'hooks' => ['https://example.com/x']},
        'schedule' => {'every' => '5m', 'remind' => {'enable' => true, 'minutes' => 0}},
      ))
    end

    # ⚠ 型違いはスキーマの担当。同じ誤りを 2 通りのメッセージで出さない。
    def test_schedule_type_error_left_to_schema
      assert_empty(SourceValidator.schedule_errors('schedule' => {'cron' => 42}))
    end

    def test_missing_required
      assert_not_empty(SourceValidator.validate('source' => {'feed' => 'https://example.com/feed'}))
      assert_false(SourceValidator.valid?('dest' => {'hooks' => ['https://example.com/x']}))
    end

    def test_unknown_property
      assert_false(SourceValidator.valid?(
        'source' => {'feed' => 'https://example.com/feed'},
        'dest' => {'lemmy' => {'host' => 'x'}},
      ))
    end

    def test_incomplete_subobject
      # mastodon は url/token 両方必須
      assert_false(SourceValidator.valid?(
        'source' => {'feed' => 'https://example.com/feed'},
        'dest' => {'mastodon' => {'url' => 'https://example.com'}},
      ))
    end

    def test_wrong_type
      assert_false(SourceValidator.valid?(
        'source' => {'feed' => 'https://example.com/feed'},
        'dest' => {'tags' => 'not-an-array'},
      ))
    end

    def test_enum_violation
      assert_false(SourceValidator.valid?(
        'source' => {'github' => {'repository' => 'a/b', 'timeline' => 'bogus'}},
        'dest' => {'hooks' => ['https://example.com/x']},
      ))
    end

    # #1473: 宛先ゼロは validate を通ってしまい、no-op success を積み続ける
    def test_dest_without_destination
      assert_false(SourceValidator.valid?(
        'source' => {'feed' => 'https://example.com/feed'},
        'dest' => {},
      ))
      assert_false(SourceValidator.valid?(
        'source' => {'feed' => 'https://example.com/feed'},
        'dest' => {'tags' => ['a']},
      ))
    end

    def test_dest_with_empty_hooks
      assert_false(SourceValidator.valid?(
        'source' => {'feed' => 'https://example.com/feed'},
        'dest' => {'hooks' => []},
      ))
    end

    # 死蔵定義（chinachu 等）は dest: {} のまま置いてあるので免除する
    def test_disabled_source_may_have_no_destination
      assert_true(SourceValidator.valid?(
        'disable' => true,
        'source' => {'github' => {'repos' => 'Chinachu/Chinachu', 'timeline' => 'commits'}},
        'dest' => {},
      ))
    end

    def test_enabled_source_needs_destination_even_if_disable_false
      assert_false(SourceValidator.valid?(
        'disable' => false,
        'source' => {'feed' => 'https://example.com/feed'},
        'dest' => {},
      ))
    end

    def test_each_destination_kind_satisfies_requirement
      [
        {'hooks' => ['https://example.com/x']},
        {'mastodon' => {'url' => 'https://example.com', 'token' => 't'}},
        {'misskey' => {'url' => 'https://example.com', 'token' => 't'}},
        {'line' => {'user_id' => 'u', 'token' => 't'}},
        {'piefed' => {
          'host' => 'h',
          'user_id' => 'u',
          'password' => 'p',
          'community_id' => 1,
        }},
        {'nostr' => {'private_key' => 'k'}},
      ].each do |dest|
        assert_true(
          SourceValidator.valid?('source' => {'feed' => 'https://example.com/feed'}, 'dest' => dest),
          "#{dest.keys.first} が宛先として認められていない",
        )
      end
    end

    def test_empty_source
      # source は最低 1 プロパティ必須
      assert_false(SourceValidator.valid?(
        'source' => {},
        'dest' => {'hooks' => ['https://example.com/x']},
      ))
    end

    # #1470: silence_tolerance は opt-in なのでスキーマ上は妥当だが、
    # 宣言しなければサイレント不発の検知が丸ごと効かない
    # 🔴 **スキーマ項目そのものを守る（レビュー R2 / M12）。**monitor は
    # additionalProperties: false なので、この項目が消えた瞬間に docs に書いた
    # 設定例が source validate / source edit で弾かれる。⚠ それを検知するテストが無かった。
    def test_valid_monitor_error_streak_threshold
      base = {
        'source' => {'feed' => 'https://example.com/feed'},
        'dest' => {'hooks' => ['https://example.com/x']},
      }

      assert_true(SourceValidator.valid?(base.merge('monitor' => {'error_streak_threshold' => 4})))
      assert_true(SourceValidator.valid?(base.merge('monitor' => {'error_streak_threshold' => 28})))
      # minimum: 1 / type: integer
      assert_false(SourceValidator.valid?(base.merge('monitor' => {'error_streak_threshold' => 0})))
      assert_false(SourceValidator.valid?(base.merge('monitor' => {'error_streak_threshold' => '4'})))
    end

    # 🔴 Codex P1 (#1558): しきい値に到達するのに retention_days より長くかかる
    # 組み合わせを弾く。⚠ **どれだけ連続で失敗しても 503 にならない**設定になる。
    def test_warnings_unreachable_error_streak_threshold
      retention = Config.instance['/monitor/retention_days']
      daily = {
        'source' => {'feed' => 'https://example.com/feed'},
        'schedule' => {'cron' => '1 0 * * *'},
        'dest' => {'hooks' => ['https://example.com/x']},
        'monitor' => {'silence_tolerance' => '7d'},
      }

      # 日次 × retention+1 回ぶん = 窓に入らない
      warnings = SourceValidator.warnings(
        daily.merge('monitor' => {'silence_tolerance' => '7d',
                                  'error_streak_threshold' => retention + 1}),
      )

      assert_equal(1, warnings.size)
      assert_match(/error_streak_threshold/, warnings.first)
      assert_match(/retention_days/, warnings.first)

      # 日次 × retention 回ぶんなら収まる
      assert_empty(SourceValidator.warnings(
        daily.merge('monitor' => {'silence_tolerance' => '7d',
                                  'error_streak_threshold' => retention}),
      ))
      # ⚠ 既定（未指定）と 1 は指摘しない
      assert_empty(SourceValidator.warnings(daily))
      assert_empty(SourceValidator.warnings(
        daily.merge('monitor' => {'silence_tolerance' => '7d', 'error_streak_threshold' => 1}),
      ))
    end

    # 🔴 **#1587 (Codex P2): 不均一な cron は「次の 2 回の間隔」で外挿できない。**
    #
    # `0 0 * * 1-5`（平日のみ）は retention 14 日の窓に **10 回**しか発火しないので、
    # しきい値 12 には到達できない。⚠ 旧実装は**隣り合う 2 回の間隔**（月曜に叩けば
    # 1 日）を全体へ引き伸ばしていたので、12 日 ≦ 14 日 と読んで見逃した。
    #
    # ⚠⚠ **`source validate` を叩いた曜日で結果が変わってはいけない。**月曜と金曜の
    # 両方で固定して、どちらでも同じ結論になることまで見る（旧実装は金曜だと
    # 3 日刻みと読むので警告が出た＝**同じ設定なのに曜日で答えが違った**）。
    def test_warnings_count_actual_cron_occurrences_regardless_of_weekday
      weekday_cron = {
        'source' => {'feed' => 'https://example.com/feed'},
        'schedule' => {'cron' => '0 0 * * 1-5'},
        'dest' => {'hooks' => ['https://example.com/x']},
        'monitor' => {'silence_tolerance' => '7d', 'error_streak_threshold' => 12},
      }

      # 2026-09-14 は月曜 / 2026-09-18 は金曜
      ['2026-09-14 12:00:00', '2026-09-18 12:00:00'].each do |at|
        warnings = with_time_frozen(Time.parse(at)) {SourceValidator.warnings(weekday_cron)}

        assert_equal(1, warnings.size, "#{at} で結論が変わっている")
        assert_match(/error_streak_threshold/, warnings.first)
        assert_match(/10 回だけ/, warnings.first, warnings.first)
      end
    end

    # 🔴 **#1587 (Codex P1): `schedule` を省いても実行時には既定で走る。**
    #
    # ⚠⚠ `IcalendarSource#default_cron` は `0 0 * * *`（日次）。旧実装は `schedule` が
    # 無いと検査ごと飛ばしていたので、**retention に収まらないしきい値を素通し**した。
    def test_warnings_use_default_cron_when_schedule_is_omitted
      retention = Config.instance['/monitor/retention_days']
      warnings = SourceValidator.warnings(
        'source' => {'ical' => 'https://example.com/c.ics'},
        'dest' => {'hooks' => ['https://example.com/x']},
        'monitor' => {'silence_tolerance' => '7d', 'error_streak_threshold' => retention + 1},
      )

      assert_equal(1, warnings.size, '既定 cron (0 0 * * *) が見えていない')
      assert_match(/error_streak_threshold/, warnings.first)
    end

    # ⚠ 一方 `Source#default_period` は `5m` なので、こちらは大きめのしきい値でも収まる。
    # **既定を見るようにしたせいで過剰に警告しない**ことまで押さえる。
    def test_warnings_use_default_period_when_schedule_is_omitted
      assert_empty(SourceValidator.warnings(
        'source' => {'feed' => 'https://example.com/feed'},
        'dest' => {'hooks' => ['https://example.com/x']},
        'monitor' => {'silence_tolerance' => '7d', 'error_streak_threshold' => 100},
      ))
    end

    # 15 分間隔ならしきい値を大きくしても収まる（本番の YouTube 系がこれ）
    def test_warnings_frequent_source_tolerates_large_threshold
      source = {
        'source' => {'feed' => 'https://example.com/feed'},
        'schedule' => {'cron' => '0,15,30,45 * * * *'},
        'dest' => {'hooks' => ['https://example.com/x']},
        'monitor' => {'silence_tolerance' => '90d', 'error_streak_threshold' => 8},
      }

      assert_empty(SourceValidator.warnings(source))
    end

    # ⚠ 壊れた schedule で警告の算出が倒れて validate 全体を止めない
    def test_warnings_survive_broken_schedule
      source = {
        'source' => {'feed' => 'https://example.com/feed'},
        'schedule' => {'cron' => 'not a cron'},
        'dest' => {'hooks' => ['https://example.com/x']},
        'monitor' => {'silence_tolerance' => '7d', 'error_streak_threshold' => 999},
      }

      assert_nothing_raised {SourceValidator.warnings(source)}
      assert_empty(SourceValidator.warnings(source))
    end

    def test_warnings_silence_tolerance_unset
      base = {
        'source' => {'feed' => 'https://example.com/feed'},
        'schedule' => {'every' => '5m'},
        'dest' => {'hooks' => ['https://example.com/x']},
      }

      assert_equal(1, SourceValidator.warnings(base).size)
      assert_empty(SourceValidator.warnings(base.merge('monitor' => {'silence_tolerance' => '7d'})))
      # 無効ソースと、一度きり投稿のソースは監視対象でないので指摘しない
      assert_empty(SourceValidator.warnings(base.merge('disable' => true)))
      assert_empty(SourceValidator.warnings(
        base.merge('schedule' => {'at' => '2026-01-01T00:00:00+09:00'}),
      ))
    end

    private

    # ⚠ **元の `Method` を保存して戻す。**`remove_method` で戻すと本物ごと消える
    # （`Time.now` は singleton class に生えている）＝ `with_sentry_stub` と同じ形。
    def with_time_frozen(time)
      original = Time.method(:now)
      Time.define_singleton_method(:now) {time}
      return yield
    ensure
      Time.define_singleton_method(:now, original)
    end
  end
end
