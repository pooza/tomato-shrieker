module TomatoShrieker
  class CommandSourceTest < TestCase
    SECRET_ENV = 'https://kuma.example.test/api/push/AbCdEf123456?status=up&msg=OK'.freeze
    SECRET_HOOK = 'https://hook.example.test/services/T000/B000/XXXXXXXX'.freeze
    SECRET_TOKEN = 'mastodon-token-0123456789'.freeze

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

    # #1692 の Codex P2: 空の `command` は走らせずに落とす（`sh -c ''` は 0 で終わる）。
    def test_exec_rejects_blank_command
      source = build_secret_source('')
      error = assert_raise(RuntimeError) {source.exec}

      assert_equal('/source/command is blank', error.message)
    end

    # 🔴 **4.16.0 リリース前レビュー: stderr に不正なバイト列があっても、その中身を理由に残す。**
    #
    # ⚠⚠ 以前は `stderr.presence` が `ArgumentError: invalid byte sequence in UTF-8` を上げ、
    # **本来の失敗の理由がすり替わっていた**（stderr の中身は run_log にも Sentry にも残らない）。
    def test_exec_reports_stderr_with_invalid_bytes
      source = build_secret_source("printf '\\223\\372 failed' >&2; exit 1")
      error = assert_raise(RuntimeError) {source.exec}

      assert_include(error.message, 'failed')
      assert_predicate(error.message, :valid_encoding?)
    end

    # ⚠ 何も書かずに落ちるコマンドは、終わり方を理由にする（以前は空のメッセージだった）。
    def test_exec_reports_exit_status_without_output
      error = assert_raise(RuntimeError) {build_secret_source('exit 3').exec}

      assert_equal('command exited with status 3', error.message)
      # ⚠ wait status の下位 7 ビットはシグナル（`exit 2` は 512）。
      assert_equal('command exited with status 2', build_source.exit_description(512))
      assert_equal('command killed by signal 9', build_source.exit_description(9))
    end

    # 🔴 #1703: 締切。未指定なら `/command/timeout/seconds`、ソースごとに秒か duration で上書きできる。
    def test_command_timeout
      assert_equal(config['/command/timeout/seconds'], build_secret_source.command_timeout)
      {5 => 5, '2m' => 120, 0 => 0}.each do |value, expected|
        params = secret_params
        params['source']['timeout'] = value

        assert_equal(expected, CommandSource.new(params).command_timeout, value.inspect)
      end
    end

    # 🔴 #1703: 戻らないコマンドは締切で落ち、取得段の失敗になる。次の実行を塞がない。
    def test_exec_stops_at_timeout
      params = secret_params('sleep 30')
      params['source']['timeout'] = 1
      source = CommandSource.new(params)
      started = Time.now

      assert_raise(Timeout::Error) {source.exec}
      # ⚠ 上流は締切 ＋ 最大 3 秒で戻る（TERM の猶予 2 ＋ 見切り 1）。
      assert_operator(Time.now - started, :<, 10)
      # ⚠ 締切で抜けた後も `@command_mutex` を握ったままにしない（同じソースのリマインドが待たされる）。
      assert_false(source.instance_variable_get(:@command_mutex).locked?)
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

    # 🔴 **#1670: 資格情報が生の形以外で出力に載っても伏せる。**`curl` などのエラーや HTTP の
    # ログ行は、URL を丸ごとではなくパスだけ・クエリ抜きで書く。JSON / HTML / URL エンコードも同じ。
    def test_command_masks_secret_variants
      command = build_secret_source.command
      [
        'GET /api/push/AbCdEf123456?status=up&msg=OK failed',
        'POST https://kuma.example.test/api/push/AbCdEf123456 failed',
        'push AbCdEf123456 rejected',
        '{"url":"https:\\/\\/kuma.example.test\\/api\\/push\\/AbCdEf123456?status=up&msg=OK"}',
        '<a href="https://kuma.example.test/api/push/AbCdEf123456?status=up&amp;msg=OK">',
        "url=#{CGI.escape(SECRET_ENV)}",
        'POST /services/T000/B000/XXXXXXXX 403',
      ].each do |line|
        masked = command.masked(line)

        assert_not_include(masked, 'AbCdEf123456', line)
        assert_not_include(masked, 'XXXXXXXX', line)
      end
    end

    # #1709 の Codex P1: URI として読めない値（`Addressable::URI::InvalidURIError`）でも、
    # エスケープした形は伏せる。
    def test_command_masks_escaped_forms_of_non_uri_secret
      secret = 'a b:c/%%&secret-0123'
      params = secret_params
      params['source']['env']['API_SECRET'] = secret
      command = CommandSource.new(params).command

      [CGI.escape(secret), CGI.escapeHTML(secret), secret.gsub('/') {'\\/'}].each do |form|
        assert_not_include(command.masked("leaked: #{form}"), 'secret-0123', form)
      end
    end

    # ⚠ URL から切り出す部分も短ければ入れない（`/` や `/api` まで伏せると読めなくなる）。
    def test_command_secret_variants_skip_short_parts
      secrets = build_secret_source.command.secrets

      assert_not_include(secrets, '/')
      assert_not_include(secrets, 'push')
    end

    # 🔴 **#1670: `exec` 自体が上げる例外も伏せる。**argv0 に資格情報を含むパスを書くと、
    # `Errno::ENOENT` のメッセージにそのまま載る。⚠ 型は元のまま（Sentry のまとまりを変えない）。
    def test_exec_masks_secrets_in_spawn_error
      source = build_secret_source(["/nonexistent/#{SECRET_TOKEN}/run"])
      error = assert_raise(Errno::ENOENT) {source.exec}

      assert_include(error.message, '/nonexistent/')
      assert_not_include(error.message, SECRET_TOKEN)
      # 🔴 伏せる前の例外を `cause` に残さない。sentry-ruby は連鎖ごと送る（4.17.0 リリース前レビュー）。
      assert_nil(error.cause)
    end

    # #1670: 宛先の資格情報は、短くても伏せる（env の値とは違い、資格情報であることが確か）。
    def test_command_secrets_keep_short_dest_secrets
      params = secret_params
      params['dest']['mastodon']['token'] = 'tk12'

      assert_include(CommandSource.new(params).command.secrets, 'tk12')
    end

    # #1670: 暗号化して書いた資格情報は、復号した値も伏せる（コマンドへ渡るのは復号した値）。
    # ⚠ 鍵（`/crypt/password`）は開発機にも CI にも無いので、ここで置く（teardown で読み直す）。
    def test_command_secrets_include_decrypted_values
      config['/crypt/password'] = 'test-crypt-password-0123'
      params = secret_params
      params['dest']['piefed'] = {
        'url' => 'https://piefed.example.test',
        'user' => 'bot',
        'password' => Crypt.new.encrypt('piefed-password-0123'),
      }

      assert_include(CommandSource.new(params).command.secrets, 'piefed-password-0123')
    end

    # 🔴 **#1670: `DEST_SECRET_KEYS` をスキーマと突き合わせる。**宛先を足したときに、
    # 資格情報のキーを足し忘れると黙って漏れる。
    def test_dest_secret_keys_match_schema
      schema = YAML.load_file(File.join(Environment.dir, 'config/schema/source.yaml'))
      keys = []
      walk = lambda do |node, path|
        (node['properties'] || {}).each do |name, child|
          keys.push("#{path}/#{name}") if name.match?(/token|password|private_key|secret/)
          walk.call(child, "#{path}/#{name}") if child.is_a?(Hash)
        end
      end
      walk.call(schema.dig('properties', 'dest'), '/dest')

      assert_equal(keys.sort, CommandRunner::DEST_SECRET_KEYS.sort)
    end

    # 🔴 **#1477: 依存が欠けていたら、登録の時点でログと Sentry に出す（起動は止めない）。**
    # ⚠ 自動の `bundle install` は `bundle` で始まるコマンドにしか走らないので、直接実行の定義
    # （本番の 7 件）はこれが無いと、走るたびに `Bundler::GemNotFound` で落ちるまで気づけない。
    def test_command_bundle_problem
      Dir.mktmpdir do |dir|
        write_missing_gem_bundle(dir)
        problem = build_secret_source(['bin/run.rb']).tap {|v| v.command.dir = dir}.command_bundle_problem

        assert_include(problem, 'bundle check failed')
        assert_include(problem, 'tomato-shrieker-missing-gem-1477')
      end
    end

    # ⚠ **Gemfile.lock も置く。**lock が無いと `bundle check` は解決のためにネットワークへ出る
    # （サテライトはどれも lock を持っている）。
    def write_missing_gem_bundle(dir, group: nil)
      gem = 'tomato-shrieker-missing-gem-1477'
      line = group ? "group :#{group} do\n  gem '#{gem}'\nend" : "gem '#{gem}'"
      File.write(File.join(dir, 'Gemfile'), "source 'https://rubygems.org'\n#{line}\n")
      File.write(File.join(dir, 'Gemfile.lock'), [
        'GEM', '  remote: https://rubygems.org/', '  specs:', "    #{gem} (0.0.1)", '',
        'PLATFORMS', '  ruby', '', 'DEPENDENCIES', "  #{gem}", ''
      ].join("\n"))
    end

    # #1714 の Codex P2: 実行時と同じ環境（`/source/env`）で見る。`BUNDLE_WITHOUT` で外した
    # グループの欠落は、コマンドが走るときにも問題にならない。
    def test_command_bundle_problem_uses_source_env
      Dir.mktmpdir do |dir|
        write_missing_gem_bundle(dir, group: 'extra')
        params = secret_params(['bin/run.rb'])
        params['source']['dir'] = dir

        assert_not_nil(CommandSource.new(params).command_bundle_problem)
        params['source']['env']['BUNDLE_WITHOUT'] = 'extra'

        assert_nil(CommandSource.new(params).command_bundle_problem)
      end
    end

    # #1714 の Codex P1（2 巡目）: `bundle` が見つからなくても上げない（起動を止めない）。
    def test_command_bundle_problem_when_bundle_is_missing
      Dir.mktmpdir do |dir|
        write_missing_gem_bundle(dir)
        params = secret_params(['/bin/true'])
        params['source']['dir'] = dir
        params['source']['env']['PATH'] = '/nonexistent'

        assert_include(CommandSource.new(params).command_bundle_problem, 'bundle check could not run')
      end
    end

    # 🔴 型の合わない env でも上げない（4.17.0 リリース前レビュー）。spawn が `TypeError` を上げると、
    # `register_all` が起動ごと倒れて全ソースが止まる。
    def test_command_bundle_problem_with_non_string_env
      Dir.mktmpdir do |dir|
        write_missing_gem_bundle(dir)
        params = secret_params(['/bin/true'])
        params['source']['dir'] = dir
        params['source']['env']['PORT'] = 3000

        assert_include(CommandSource.new(params).command_bundle_problem, 'bundle check could not run')
      end
    end

    # #1714 の Codex P1: 存在しない `dir` のパスに資格情報が入っていても伏せる。
    def test_command_bundle_problem_masks_dir
      params = secret_params
      params['source']['dir'] = "/nonexistent/#{SECRET_TOKEN}"
      problem = CommandSource.new(params).command_bundle_problem

      assert_include(problem, 'dir not found')
      assert_not_include(problem, SECRET_TOKEN)
    end

    # ⚠ Gemfile の無い `dir` は見ない。存在しない `dir` は問題として返す（走らせると必ず落ちる）。
    def test_command_bundle_problem_without_gemfile
      Dir.mktmpdir do |dir|
        assert_nil(build_secret_source.tap {|v| v.command.dir = dir}.command_bundle_problem)
      end
      params = secret_params
      params['source']['dir'] = '/nonexistent/__test_1477__'

      assert_equal('/source/dir not found: /nonexistent/__test_1477__', CommandSource.new(params).command_bundle_problem)
    end

    # ⚠ 検査は登録を止めない（ログに出して、そのまま登録する）。
    def test_register_continues_when_bundle_is_broken
      source = build_secret_source
      source.define_singleton_method(:command_bundle_problem) {'bundle check failed in /x: missing'}
      registered = false
      source.define_singleton_method(:schedule) {|*| registered = true}
      source.register

      assert_true(registered)
    end

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
