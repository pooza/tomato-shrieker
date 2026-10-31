module TomatoShrieker
  # #1559: ソース種別ごとの既定値。
  class SourceDefaultsTest < TestCase
    # ⚠ `config/local.yaml` と同じ形から `key_flatten` を通す（`Config` の読み込みと同じ）。キーを
    # 手で書くと、小文字になることを素通りして、実物では効かないのに緑になる（4.19.0 リリース前レビュー）。
    DEFAULTS = {
      'source_defaults' => {
        'TextSource' => {
          'monitor' => {'error_streak_threshold' => 28, 'silence_tolerance' => '30d'},
          'schedule' => {'retry' => {'times' => 2, 'interval' => '10m'}},
        },
      },
    }.freeze

    def setup
      flat_defaults.each {|path, value| config[path] = value}
    end

    def teardown
      clear_defaults
      super
    end

    def flat_defaults
      return DEFAULTS.key_flatten
    end

    def clear_defaults
      flat_defaults.each_key {|path| config.delete(path)}
    end

    def text_source(extra = {})
      return TextSource.new({
        'id' => '__test_source_defaults__',
        'source' => {'text' => 'body'},
        'dest' => {'hooks' => ['https://hook.example.test/x']},
      }.merge(extra))
    end

    def test_defaults_are_applied
      source = text_source

      assert_equal(28, source.monitor_error_streak_threshold)
      assert_equal(2, source.send(:retry_times))
      assert_equal('10m', source.send(:retry_interval))
      assert_equal(30 * 86_400, source.monitor_silence_tolerance_seconds)
    end

    # 定義にあるキーは定義が勝ち、無いキーだけが既定から来る。
    def test_declared_key_wins_per_key
      source = text_source('monitor' => {'error_streak_threshold' => 3}, 'schedule' => {'retry' => {'times' => 5}})

      assert_equal(3, source.monitor_error_streak_threshold)
      assert_equal(5, source.send(:retry_times))
      assert_equal('10m', source.send(:retry_interval))
      assert_false(source.source_defaults.key?('monitor/error_streak_threshold'))
      assert_equal('30d', source.source_defaults['monitor/silence_tolerance'])
    end

    # `null` を書けば、そのソースだけ既定を外せる。
    def test_null_opts_out
      source = text_source('monitor' => {'silence_tolerance' => nil}, 'schedule' => {'retry' => nil})

      assert_nil(source.monitor_silence_tolerance_seconds)
      assert_equal(0, source.send(:retry_times))
      assert_equal(['monitor/error_streak_threshold'], source.source_defaults.keys)
    end

    # ⚠ 継承しない（規則を単純に保つ）。
    def test_applies_only_to_the_exact_class
      config['/source_defaults/feedsource/monitor/error_streak_threshold'] = 99
      source = YouTubeChannelSource.new({'id' => 'x', 'source' => {'youtube' => {'channel' => {'id' => 'y'}}}})

      assert_empty(source.source_defaults)
    ensure
      config.delete('/source_defaults/feedsource/monitor/error_streak_threshold')
    end

    # ⚠ 空の値（`tolerance:`）で `Source.new` を倒さない。全ソースが止まる。
    def test_empty_default_is_ignored
      config['/source_defaults/textsource/monitor/tolerance'] = nil

      assert_false(text_source.source_defaults.key?('monitor/tolerance'))
    ensure
      config.delete('/source_defaults/textsource/monitor/tolerance')
    end

    # ⚠ スキーマ違反の定義でも `Source.new` を倒さず、無効のつもりを有効に反転させない。
    def test_non_hash_parent_is_left_alone
      assert_nothing_raised {text_source('schedule' => '5m', 'monitor' => 'x')}
      assert_equal(0, text_source('schedule' => {'retry' => false}).send(:retry_times))
    end

    # ⚠ 元の定義は `/sources` の実物なので書き換えない。
    def test_does_not_mutate_the_definition
      params = {'source' => {'text' => 'body'}, 'schedule' => {'cron' => '1 0 * * *'}}
      TextSource.new(params)

      assert_equal({'cron' => '1 0 * * *'}, params['schedule'])
      assert_false(params.key?('monitor'))
    end

    # id の無い定義の id は定義の SHA1。既定値を変えても id（＝ Entry の feed）を変えない。
    def test_id_ignores_defaults
      params = {'source' => {'text' => 'body'}}
      with_defaults = TextSource.new(params).id
      clear_defaults
      without_defaults = TextSource.new(params).id

      assert_equal(without_defaults, with_defaults)
    end

    # 既定値の変更は digest に出す（再起動で定義が変わることを `pending_sources.sh` で見られる）。
    def test_digest_follows_defaults
      with_defaults = Scheduler.digest([text_source])
      clear_defaults
      without_defaults = Scheduler.digest([text_source])

      assert_not_equal(without_defaults, with_defaults)
    end

    def test_status_reports_defaulted_keys
      row = SourceStatus.new(text_source('monitor' => {'error_streak_threshold' => 3})).to_h

      assert_equal(
        {
          'monitor/silence_tolerance' => '30d',
          'schedule/retry/times' => 2,
          'schedule/retry/interval' => '10m',
        },
        row[:source_defaults],
      )
    end

    # ⚠ スキーマはクラス名を列挙している。ソースクラスを足したら揃える。
    def test_schema_lists_every_source_class
      listed = base_schema.dig('properties', 'source_defaults', 'properties').keys
      names = Source.classes.map {|v| v[:class].name.split('::').last}

      assert_equal(names.uniq.sort, listed.sort)
    end

    def test_schema_rejects_typos
      assert_empty(schema_errors('TextSource' => {'monitor' => {'error_streak_threshold' => 3}}))
      assert_not_empty(schema_errors('TextSauce' => {}))
      assert_not_empty(schema_errors('TextSource' => {'schedule' => {'cron' => '1 0 * * *'}}))
      assert_not_empty(schema_errors('TextSource' => {'monitor' => {'silence_tolerance' => '*/5 * * * *'}}))
      assert_not_empty(schema_errors('TextSource' => {'monitor' => {'tolerance' => 'abc'}}))
    end

    def base_schema
      return YAML.load_file(File.join(Environment.dir, 'config/schema/base.yaml'))
    end

    def schema_errors(defaults)
      return JSON::Validator.fully_validate(base_schema, {'source_defaults' => defaults})
    end
  end
end
