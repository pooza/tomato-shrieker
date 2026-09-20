module TomatoShrieker
  class CommandSourceTest < TestCase
    def test_command
      CommandSource.all.reject(&:disable?).each do |source|
        assert_kind_of(Ginseng::CommandLine, source.command)
        source.command.exec

        assert_predicate(source.command.status, :zero?)
      end
    end

    # 🔴🔴 **#1586: エントリ処理段で落ちた run は `entry_stage` が立つ。**
    #
    # ⚠⚠ CommandSource は `create_template` で落ちると `@delivery_stats` が空のまま
    # `exec_with_run_log` の rescue に入るので、**`shrieker_errors` が空の error 行**に
    # なる。`shrieker_errors` の有無を「取得段の失敗」の代理にしていた 4.9.0 までは、
    # この失敗で**緩めたしきい値がそのまま残っていた**（#1583 の Codex P1）。
    #
    # ⚠ **`command` は差し替える。**`CommandSource#command` は `/ruby/jit` を読むが
    # これが未宣言の必須キーで、設定していない環境では `ConfigError` になる（#1614）。
    def test_entry_stage_marked_after_reading_output
      source = build_source
      stub_command(source, ['echo', 'フィクスチャ 1'])
      stats = attach_stats(source)
      def source.create_template(*)
        raise 'template broken'
      end

      assert_raise(RuntimeError) {source.exec}
      assert_true(stats.entry_stage?, 'コマンドの出力を読んだ後で落ちている')
      # ⚠ 代理（shrieker_errors）では捕まらないことを同時に示す
      assert_empty(stats.shrieker_errors)
    end

    # ⚠ コマンド自体が落ちた run は**取得段**。緩和が効いてよい側なので段を立てない。
    def test_entry_stage_not_marked_when_command_fails
      source = build_source
      stub_command(source, ['sh', '-c', 'exit 1'])
      stats = attach_stats(source)

      assert_raise(RuntimeError) {source.exec}
      assert_false(stats.entry_stage?)
    end

    # ⚠ 出力が空の run も段を立てない。失うものが無い run で緩和を潰さない。
    def test_entry_stage_not_marked_without_output
      source = build_source
      stub_command(source, ['true'])
      stats = attach_stats(source)
      source.exec

      assert_false(stats.entry_stage?)
    end

    def build_source
      return CommandSource.new(
        'id' => '__test_command_entry_stage__',
        'source' => {'command' => 'echo フィクスチャ 1'},
        'schedule' => {'every' => '1d'},
        'dest' => {'hooks' => ['https://hook.example.test/command']},
      )
    end

    def stub_command(source, args)
      command = Ginseng::CommandLine.new
      command.args = args
      source.define_singleton_method(:command) {command}
    end

    def attach_stats(source)
      stats = DeliveryStats.new
      source.instance_variable_set(:@delivery_stats, stats)
      return stats
    end

    def test_delimiter
      CommandSource.all.reject(&:disable?).each do |source|
        assert_kind_of(Regexp, source.delimiter)
      end
    end

    def test_bundler?
      CommandSource.all.reject(&:disable?).each do |source|
        assert_boolean(source.bundler?)
      end
    end
  end
end
