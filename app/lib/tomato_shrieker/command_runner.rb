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

    def command?
      return command_params['command'].present?
    end

    # コマンドを走らせて標準出力を返す。非 0 で終わったら例外。
    def run_command
      Bundler.with_unbundled_env {command.exec}
      # ⚠ 失敗したコマンドは、渡された資格情報を stderr に書き返すことがある（`curl` など）。
      # 例外メッセージは run_log・`/status.json`・Sentry へ流れるので、ここでも伏せる (#1623)。
      # ⚠ stderr は空でも String なので `||` では stdout へ倒れない（理由を stdout にだけ書いて
      # 非 0 で終わるコマンドの例外メッセージが空になっていた）。
      raise command.masked(command.stderr.presence || command.stdout) unless command.status.zero?
      return command.stdout
    end

    def bundler?
      return command.to_s.match?(/^bundler? /)
    end

    def install_command_bundle
      return unless bundler?
      Bundler.with_unbundled_env {command.bundle_install}
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
    def command_secrets
      values = (command_params['env'] || {}).values
      values.concat(DEST_SECRET_KEYS.map {|key| self[key]})
      values.concat((self['/dest/hooks'] || []).map {|hook| hook.is_a?(Hash) ? hook['url'] : hook})
      return values.compact.map(&:to_s).select {|v| v.length >= SECRET_MIN_LENGTH}
    end
  end
end
