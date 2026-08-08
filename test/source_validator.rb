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
