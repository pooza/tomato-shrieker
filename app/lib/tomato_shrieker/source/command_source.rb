module TomatoShrieker
  class CommandSource < Source
    # これより短い値は `secrets` に入れない。⚠ `DEBUG: '1'` のような短い env の値まで伏せると、
    # ログと例外メッセージの同じ文字が全部 `[FILTERED]` になり、障害の原因が読めなくなる。
    SECRET_MIN_LENGTH = 8

    # 宛先の資格情報が入るキー（`dest` の下）。⚠ 宛先を足したらここにも足す。
    DEST_SECRET_KEYS = [
      '/dest/mastodon/token', '/dest/misskey/token', '/dest/line/token',
      '/dest/piefed/password', '/dest/nostr/private_key'
    ].freeze

    def exec
      Bundler.with_unbundled_env {command.exec}
      # ⚠ 失敗したコマンドは、渡された資格情報を stderr に書き返すことがある（`curl` など）。
      # 例外メッセージは run_log・`/status.json`・Sentry へ流れるので、ここでも伏せる (#1623)。
      raise command.masked(command.stderr || command.stdout) unless command.status.zero?
      # 🔴 **ここから先はエントリ処理段 (#1586)。**⚠⚠ コマンドの出力は日付に依存する
      # ものがあり（dqdai-anniv 等）、落ちたぶんは**次の run で取り返せない**。
      # ⚠ 上の `raise command.stderr` までは取得段なので段を立てない。
      statuses = command.stdout.split(delimiter).map(&:strip).select(&:present?)
      @delivery_stats&.enter_entry_stage! if statuses.present?
      statuses.each do |status|
        template = create_template(:default, status)
        shriek(template:, visibility:)
      end
    end

    def bundler?
      return command.to_s.match?(/^bundler? /)
    end

    def delimiter
      return Regexp.new("#{self['/source/delimiter'] || '====='}\n?")
    end

    def command
      unless @command
        @command = Ginseng::CommandLine.new(command_args)
        @command.dir = self['/source/dir'] || Environment.dir
        @command.env = @params.dig('source', 'env') || {}
        @command.secrets = command_secrets
        @command.env['RUBY_YJIT_ENABLE'] = 'yes' if config['/ruby/jit']
        @command.env['BUNDLE_GEMFILE'] = File.join(@command.dir, 'Gemfile')
        @command.env['RACK_ENV'] ||= Environment.type
      end
      return @command
    end

    # 配列はそのまま argv、文字列は `sh -c` で実行する。
    def command_args
      return self['/source/command'] if self['/source/command'].is_a?(Array)
      return ['sh', '-c', self['/source/command']]
    end

    # ログに出す前に伏せる値 (#1623)。`Ginseng::CommandLine` の伏せ字は opt-in で、
    # 渡さないと引数と env がそのまま `/var/log/tomato-shrieker.log` に出る。
    #
    # 🔴 **`source.env` の値は、キー名を見ずに全部入れる。**上流の `Masking#mask` は
    # キー名（`TOKEN` など）で判定するので、`PUSH_URL` のような名前の値は素通りする。
    # ⚠ 宛先の資格情報（webhook URL・トークン）も入れる。コマンドの引数へ書き写して
    # 渡す定義を書いても、黙って漏れない。
    def command_secrets
      values = (@params.dig('source', 'env') || {}).values
      values.concat(DEST_SECRET_KEYS.map {|key| self[key]})
      values.concat((self['/dest/hooks'] || []).map {|hook| hook.is_a?(Hash) ? hook['url'] : hook})
      return values.compact.map(&:to_s).select {|v| v.length >= SECRET_MIN_LENGTH}
    end

    def register
      Bundler.with_unbundled_env {command.bundle_install} if bundler?
      return super
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.grep(self).each(&block)
    end
  end
end
