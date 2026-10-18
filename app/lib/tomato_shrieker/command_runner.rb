module TomatoShrieker
  # コマンドを子プロセスで走らせるソースが共有する部分 (#1691)。
  #
  # `CommandSource`（出力をそのまま投稿する）と `IcalendarSource`（出力を iCalendar として
  # 読む）が使う。⚠ **コマンドの組み立て（`dir`・bundler・環境変数・伏せ字）を複製しない**
  # ため。違うのは設定の置き場所（`command_root`）だけ。
  module CommandRunner
    # これより短い値は `secrets` に入れない。⚠ `DEBUG: '1'` のような短い env の値まで伏せると、
    # ログと例外メッセージの同じ文字が全部 `[FILTERED]` になり、障害の原因が読めなくなる。
    SECRET_MIN_LENGTH = 8

    # 宛先の資格情報が入るキー（`dest` の下）。⚠ 宛先を足したらここにも足す。
    DEST_SECRET_KEYS = [
      '/dest/mastodon/token', '/dest/misskey/token', '/dest/line/token',
      '/dest/piefed/password', '/dest/nostr/private_key'
    ].freeze

    # `command` / `dir` / `env` を置く場所。
    def command_root
      return '/source'
    end

    # ⚠ **Hash でなければ空を返す。**`IcalendarSource` の `/source/ical` は URL（文字列）の
    # こともある。
    def command_params
      params = @params.dig(*command_root.split('/').reject(&:empty?))
      return params.is_a?(Hash) ? params : {}
    end

    # ⚠ **キーの有無で見る（#1692 の Codex P2）。**`present?` で見ると、空の `command`
    # （`''` / `[]`）を書いた定義が「コマンドではない」側へ流れる。
    def command?
      return command_params.key?('command')
    end

    # 🔴 **コマンドの実行は 1 本ずつ（4.16.0 リリース前レビュー）。**`command`（メモ化した
    # `Ginseng::CommandLine`）は `exec` の冒頭で `@stdout` / `@status` を nil に戻す。
    # `IcalendarSource` は日次の `exec` とリマインドが別々のジョブ（別スレッド）なので、
    # 片方が結果を読む前にもう片方が走り出すと、nil や相手の結果を読む。
    def initialize(params)
      super
      @command_mutex = Mutex.new
    end

    # コマンドを走らせて標準出力を返す。非 0 で終わったら例外。
    #
    # 🔴 **空の `command` は例外にする（#1692 の Codex P2）。**`sh -c ''` は何も出さずに 0 で
    # 終わるので、そのまま走らせると壊れた定義が「出力なし」の success を積み続ける。
    # ⚠ スキーマでも弾くが、`source reload` はスキーマを見ない。
    def run_command
      raise "#{command_root}/command is blank" if command_blank?
      stdout, stderr, status = capture_command
      return stdout if status.zero?
      # ⚠ 失敗したコマンドは、渡された資格情報を stderr に書き返すことがある（`curl` など）。
      # 例外メッセージは run_log・`/status.json`・Sentry へ流れるので、ここでも伏せる (#1623)。
      # ⚠ stderr は空でも String なので `||` では stdout へ倒れない（理由を stdout にだけ書いて
      # 非 0 で終わるコマンドの例外メッセージが空になっていた）。
      # ⚠ 何も書かずに落ちるコマンドもある。そのときは終わり方だけでも残す。
      raise command.masked(stderr.presence || stdout.presence || exit_description(status))
    end

    # 🔴 **出力は受け取った直後に `scrub` する（4.16.0 リリース前レビュー）。**子プロセスの
    # 出力はエンコーディングが不定で、不正なバイト列（Shift_JIS の stderr など）があると
    # `presence` / `blank?` / `split` が `ArgumentError` を上げる。⚠⚠ そうなると**本来の失敗の
    # 理由が `invalid byte sequence` にすり替わり**、stderr の中身はどこにも残らない。
    #
    # 🔴 **`exec` が上げた例外も伏せる (#1670)。**argv0 や `dir` に資格情報を含むパスを書くと、
    # `Errno::ENOENT` のメッセージにそのまま載る。⚠ 型とバックトレースは元のまま。
    #
    # 🔴🔴 **`cause` を付けない（4.17.0 リリース前レビュー）。**`rescue` の中で投げ直すと、伏せる前の
    # 例外が `cause` に付き、sentry-ruby が連鎖ごと送る＝ **Sentry にだけ平文で届いていた**。
    # ⚠ `e.exception(msg)` は複製なので、元の例外がすでに持つ `cause` も残る（`raise ..., cause: nil`
    # でも消えない）。**同じクラスの新しいインスタンスを作り、`rescue` の外で投げる。**
    def capture_command
      error = nil
      result = @command_mutex.synchronize do
        Bundler.with_unbundled_env {command.exec}
        [command.stdout.to_s.scrub, command.stderr.to_s.scrub, command.status]
      rescue => e
        error = masked_exception(e)
        nil
      end
      raise error if error
      return result
    end

    def masked_exception(error)
      masked = error.class.allocate.exception(command.masked(error.message))
      masked.set_backtrace(error.backtrace)
      return masked
    end

    # ⚠ `status` は wait status（`exit 2` が 512）。下位 7 ビットはシグナル。
    def exit_description(status)
      return "command exited with status #{status >> 8}" if status.nobits?(0x7f)
      return "command killed by signal #{status & 0x7f}"
    end

    def command_blank?
      value = command_params['command']
      return value.all?(&:blank?) if value.is_a?(Array)
      return value.blank?
    end

    def bundler?
      return command.to_s.match?(/^bundler? /)
    end

    def install_command_bundle
      return unless bundler?
      Bundler.with_unbundled_env {command.bundle_install}
    end

    # 登録の前の準備。`bundle` で始まるコマンドなら依存を入れ、どれも依存を検査する。
    def prepare_command
      install_command_bundle
      check_command_bundle
    end

    # 🔴 **登録の時点で、コマンドの依存が壊れていないかを見る (#1477)。**
    #
    # ⚠⚠ 自動の `bundle install` は `bundle` で始まるコマンドにしか走らず、本番の定義
    # （`bin/loquat.rb` のような直接実行）では一度も発火していない。Ruby を上げてサテライトの
    # `bundle install` を忘れると、**登録は通って、走るたびに `Bundler::GemNotFound` で落ちる**
    # （2026-08-03 に 7 ソースが約 24 時間）。
    # ⚠ **検査するだけ。**起動は止めず、直しもしない（デプロイ漏れをコードで隠さない）。
    # 見つけたらログと Sentry に出す。
    def check_command_bundle
      return unless problem = command_bundle_problem
      error = RuntimeError.new(problem)
      logger.error(source: id, class: self.class.to_s, error:)
      Sentry.capture_exception(error, tags: {source: id}) if Sentry.initialized?
    end

    # 依存の問題の説明。無ければ nil。⚠ デプロイ前の確認（deploy スキルの `enabled_sources.rb`）
    # からも呼ぶ。⚠ 子プロセスと同じく bundler の痕跡を消した環境で、`dir` の Gemfile を見る
    # ⚠ `RBENV_VERSION` は `child_env` が外すが、rbenv が版の bin を `PATH` の先頭に置いているので、
    # 本体と同じ Ruby の gem を見る。
    #
    # 🔴 **`Bundler.with_unbundled_env` で囲まない。**あれはプロセス全体の `ENV` を差し替えて
    # 戻すので、**`register` は並列（`Scheduler#apply` の `Parallel.map`）だから、別のスレッドが
    # 差し替え後の `ENV` を控えて戻し、`ENV` が消える**（テストで `ENV['TEST']` が消えて実際に
    # 踏んだ）。子プロセスに渡す環境だけを組み立てて `unsetenv_others` で渡す。
    def command_bundle_problem
      dir = command.dir
      # ⚠ パスにも資格情報が入りうる（#1714 の Codex P1）。実行時の spawn の例外と同じく伏せる。
      return command.masked("#{command_root}/dir not found: #{dir}") unless File.directory?(dir)
      gemfile = File.join(dir, 'Gemfile')
      return nil unless File.exist?(gemfile)
      # 🔴 **実行時と同じ環境で見る（#1714 の Codex P2）。**`/source/env` の `BUNDLE_PATH` /
      # `GEM_HOME` などは結果を変える。上流が子へ渡す `child_env`（`RBENV_VERSION` 等を外し、
      # ソースの env と `BUNDLE_GEMFILE` を重ねたもの）をそのまま使う。
      env = Bundler.unbundled_env.merge(command.send(:child_env), 'BUNDLE_GEMFILE' => gemfile)
      output, status = Open3.capture2e(env, 'bundle', 'check', chdir: dir, unsetenv_others: true)
      return nil if status.success?
      detail = output.to_s.scrub.lines.map(&:strip).reject(&:empty?).join(' ').ellipsize(300)
      return command.masked("bundle check failed in #{dir}: #{detail}")
    rescue => e
      # 🔴 **走らせられなかったことも問題として返す。上げない（#1714 の Codex P1）。**ソースの env が
      # `PATH` を差し替えて `bundle` が見つからないと `Errno::ENOENT` になり、上げると
      # `register_all` が起動ごと倒れる（この検査は起動を止めない約束）。
      # ⚠ `SystemCallError` だけでは足りない（4.17.0 リリース前レビュー）。env の値が文字列でない
      # （`PORT: 3000`）と spawn が `TypeError`、NUL を含むと `ArgumentError`、`dir` が文字列でないと
      # `File.directory?` が `TypeError` を上げる。
      return command.masked("bundle check could not run in #{dir}: #{e.class}")
    end

    def command
      unless @command
        @command = Ginseng::CommandLine.new(command_args)
        @command.dir = command_params['dir'] || Environment.dir
        # 🔴 **複製して渡す（4.14.0 リリース前レビュー）。**`CommandLine#env=` の `to_h` は Hash に
        # 対して自分を返すので、そのまま渡すと下の `BUNDLE_GEMFILE` / `RACK_ENV` が**定義の側へ
        # 書き戻る**。同じ定義から次に作ったインスタンスは、それを env の値として
        # `command_secrets` に拾い、Gemfile のパスや `production` を例外メッセージから伏せる。
        @command.env = (command_params['env'] || {}).dup
        @command.secrets = command_secrets
        @command.env['RUBY_YJIT_ENABLE'] = 'yes' if config['/ruby/jit']
        @command.env['BUNDLE_GEMFILE'] = File.join(@command.dir, 'Gemfile')
        @command.env['RACK_ENV'] ||= Environment.type
      end
      return @command
    end

    # 配列はそのまま argv、文字列は `sh -c` で実行する。
    def command_args
      return command_params['command'] if command_params['command'].is_a?(Array)
      return ['sh', '-c', command_params['command']]
    end

    # ログに出す前に伏せる値 (#1623)。`Ginseng::CommandLine` の伏せ字は opt-in で、
    # 渡さないと引数と env がそのまま `/var/log/tomato-shrieker.log` に出る。
    #
    # 🔴 **env の値は、キー名を見ずに全部入れる。**上流の `Masking#mask` は
    # キー名（`TOKEN` など）で判定するので、`PUSH_URL` のような名前の値は素通りする。
    # ⚠ 宛先の資格情報（webhook URL・トークン）も入れる。コマンドの引数へ書き写して
    # 渡す定義を書いても、黙って漏れない。
    #
    # ⚠ **宛先の資格情報には `SECRET_MIN_LENGTH` を掛けない (#1670)。**短くても資格情報で
    # あることは確かなので、読みやすさより伏せる側を取る。
    def command_secrets
      values = (command_params['env'] || {}).values.compact.map(&:to_s)
        .select {|v| v.length >= SECRET_MIN_LENGTH}
      values.concat(dest_secrets)
      return values.flat_map {|v| secret_variants(v)}.uniq
    end

    # 🔴 **暗号化して書いた資格情報は、復号した値も入れる (#1670)。**コマンドへ渡るのも、
    # 宛先が使うのも復号した値。⚠ 復号できなければ平文で書かれている。
    def dest_secrets
      values = DEST_SECRET_KEYS.filter_map {|key| self[key]&.to_s}
      values.concat(values.filter_map {|v| Crypt.new.decrypt(v) rescue nil})
      values.concat((self['/dest/hooks'] || []).map {|hook| hook.is_a?(Hash) ? hook['url'] : hook})
      return values.compact.map(&:to_s).reject(&:empty?)
    end

    # 資格情報が出力に載るときの、生の形以外の形 (#1670)。上流の `masked` が当てるのは生の形と
    # shellescape した形だけなので、ここで足す。
    #
    # - URL: パス＋クエリ・クエリ抜きの URL・パス・最後のパスセグメント（`curl` などのエラーや
    #   HTTP のログ行は、URL を丸ごとではなくこの形で書く）
    # - JSON の `\/`・HTML の `&amp;`・URL エンコード
    #
    # ⚠ 切り出した部分は `SECRET_MIN_LENGTH` 未満なら入れない（`/` や `api` まで伏せない）。
    def secret_variants(value)
      variants = [value, *url_secret_parts(value)]
      variants.concat(variants.map {|v| v.gsub('/') {'\\/'}})
      variants.concat(variants.map {|v| CGI.escapeHTML(v)})
      variants.push(CGI.escape(value))
      return variants.uniq
    end

    # ⚠ **URI として読めない値でも、上のエスケープ形は作る（#1709 の Codex P1）。**解析の失敗で
    # 抜けてよいのは URL から切り出す部分だけ。
    def url_secret_parts(value)
      uri = Ginseng::URI.parse(value)
      return [] unless uri&.absolute? && uri.host
      stripped = uri.dup
      stripped.query = nil
      stripped.fragment = nil
      parts = [uri.request_uri, uri.path, uri.path.split('/').last, stripped.to_s]
      return parts.compact.select {|v| v.length >= SECRET_MIN_LENGTH}
    rescue Addressable::URI::InvalidURIError
      return []
    end
  end
end
