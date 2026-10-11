module TomatoShrieker
  class CommandSourceTest < TestCase
    # 🔴 **#1614: CI でも 1 本は回ること。**`test/sources/command.yaml` が無いと
    # 下のループは 1 度も回らず、何も確かめずに緑になる（#1593 の族）。
    def test_fixture_loaded
      assert_predicate(CommandSource.all.count {|v| !v.disable?}, :positive?)
    end

    # #1614: `/ruby/jit` が既定値を持つこと。未宣言だと `command` が ConfigError になる
    def test_ruby_jit_declared
      assert_boolean(config['/ruby/jit'])
    end

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
    # ⚠ **`command` は差し替える。**実コマンドを走らせると、この run の結果が
    # コマンドの成否に左右される。
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

    # 🔴 **#1623: 引数・env に渡した資格情報が、ログに出す文字列から伏せられること。**
    # ⚠ `Ginseng::CommandLine` の伏せ字は opt-in。`secrets` を渡さないと素通しになる。
    # ⚠ env のキー名は `PUSH_URL`（上流の `Masking#mask` がキー名では拾えない形）にしてある。
    def test_command_masks_secrets
      command = build_secret_source.command

      [SECRET_ENV, SECRET_HOOK, SECRET_TOKEN].each do |secret|
        assert_include(command.secrets, secret)
        assert_not_include(command.masked(command.to_s), secret)
      end
      assert_not_include(command.send(:masked_env).values.join, SECRET_ENV)
    end

    # ⚠ **`CommandLine#to_s` は引数を shellescape して出す**（`?` → `\?`）。上流の `masked` は
    # 生の形と shellescape した形の両方を当てるので、メタ文字入りの URL も伏せられる
    # （#1662 の Codex P1 への回答。`SECRET_ENV` に `?` `=` `&` を入れてある）。
    def test_command_masks_shell_escaped_secrets
      [build_secret_source, build_secret_source(['notify', "--url=#{SECRET_ENV}"])].each do |source|
        line = source.command.to_s

        assert_include(line, '\\?status\\=up\\&msg\\=OK', 'shellescape された形でログに出る前提が崩れている')
        assert_not_include(source.command.masked(line), 'AbCdEf123456')
        assert_not_include(source.command.masked(line), 'status')
      end
    end

    # 🔴 **同じ定義から何度作っても `secrets` が変わらない（4.14.0 リリース前レビュー）。**
    # ⚠ `/source/env` の Hash をそのまま `CommandLine` に渡すと、`BUNDLE_GEMFILE` / `RACK_ENV` が
    # 定義の側へ書き戻り、2 個目から Gemfile のパスや `production` まで伏せていた。
    def test_command_does_not_mutate_source_env
      params = secret_params
      first = CommandSource.new(params).command.secrets
      second = CommandSource.new(params).command.secrets

      assert_equal(first, second)
      assert_equal(['DEBUG', 'PUSH_URL'], params.dig('source', 'env').keys.sort)
    end

    # ⚠ stderr が空（nil ではない）でも、stdout に書かれた理由を例外メッセージに載せる。
    def test_exec_reports_stdout_when_stderr_is_empty
      source = build_secret_source('echo "only on stdout"; exit 2')
      error = assert_raise(RuntimeError) {source.exec}

      assert_include(error.message, 'only on stdout')
    end

    # ⚠ 短い値まで伏せると、ログの同じ文字が全部 `[FILTERED]` になって読めなくなる。
    def test_command_secrets_skips_short_values
      assert_not_include(build_secret_source.command.secrets, '1')
    end

    # 失敗したコマンドが stderr に書き返した資格情報を、例外メッセージに載せない。
    def test_exec_masks_secrets_in_error
      source = build_secret_source('echo "denied: $PUSH_URL" >&2; exit 1')
      error = assert_raise(RuntimeError) {source.exec}

      assert_include(error.message, 'denied')
      assert_not_include(error.message, SECRET_ENV)
    end

    SECRET_ENV = 'https://kuma.example.test/api/push/AbCdEf123456?status=up&msg=OK'.freeze
    SECRET_HOOK = 'https://hook.example.test/services/T000/B000/XXXXXXXX'.freeze
    SECRET_TOKEN = 'mastodon-token-0123456789'.freeze

    def build_secret_source(script = nil)
      return CommandSource.new(secret_params(script))
    end

    def secret_params(script = nil)
      script ||= "notify #{SECRET_HOOK} #{SECRET_TOKEN} #{SECRET_ENV}"
      return {
        'id' => '__test_command_secrets__',
        'source' => {'command' => script, 'env' => {'PUSH_URL' => SECRET_ENV, 'DEBUG' => '1'}},
        'schedule' => {'every' => '1d'},
        'dest' => {
          'hooks' => [{'url' => SECRET_HOOK}],
          'mastodon' => {'url' => 'https://mastodon.example.test', 'token' => SECRET_TOKEN},
        },
      }
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
