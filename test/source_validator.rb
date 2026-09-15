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
  end
end
