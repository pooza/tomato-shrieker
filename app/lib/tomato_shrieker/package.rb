module TomatoShrieker
  module Package
    def environment_class
      return Environment
    end

    def package_class
      return Package
    end

    def config_class
      return Config
    end

    def config
      return Config.instance
    end

    def logger_class
      return Logger
    end

    def logger
      @logger ||= Logger.new
      return @logger
    end

    def http_class
      return HTTP
    end

    def self.name
      return 'tomato-shrieker'
    end

    def self.version
      return Config.instance['/package/version']
    end

    def self.url
      return Config.instance['/package/url']
    end

    def self.full_name
      return "#{name} #{version}"
    end

    def self.user_agent
      return "#{name}/#{version} (#{url})"
    end

    # 例外を人が読む 1 行にする。**例外メッセージを外へ出すときは必ずここを通す** (#1469)。
    #
    # ⚠ Sequel / SQLite の例外メッセージは ASCII-8BIT で上がる。日本語を含む SQL が
    # 失敗すると "#{error.class}: #{error.message}" は非 ASCII バイトを持つ ASCII-8BIT
    # 文字列になる。中身が妥当な UTF-8 でも JSON.generate は BINARY として警告を出し、
    # json 3.0 では例外になる。不正バイトが混じれば json 2.x でも今すぐ
    # JSON::GeneratorError で落ちる。
    #
    # 🔴 これが通る経路は監視の異常時だけなので、壊れていても平常時には気付けない。
    # 「エラーを報告しようとして同じ例外を踏む」を避けるため、rescue 節の中でも通す。
    def self.error_message(error)
      return nil unless error
      return mask_credentials("#{error.class}: #{error.message}".to_utf8)
    end

    # 🔴 **例外メッセージに埋まった資格情報を落とす (#1511)。**
    #
    # アプリは URL を丸ごとメッセージへ埋める。
    #
    #   raise Ginseng::GatewayError, "Invalid feed #{id} (#{uri}) #{e.message}"
    #
    # ここを通った文字列は **`source_run_log.error_message` に保存され**、
    # `/status.json` と `/healthz/source` からそのまま読める。⚠ 本番の
    # `monitor.bind` は `0.0.0.0` なので、LAN / VPN の誰からでも見える (#1531)。
    #
    # ⚠⚠ **`to_utf8` の後に通すこと。** 不正なバイト列のまま gsub すると
    # ArgumentError になり、**マスクごと素通りする** (#518 で踏んだ型)。
    #
    # ⚠ マスクの正本は `Ginseng::Masking`。ここで同等品を書かない (#1467)。
    def self.mask_credentials(message)
      return Logger.new.mask_urls_in(message)
    rescue => e
      # 🔴 **fail closed。** マスクを通せなかった文字列は出さない。素通しにすると
      # 伏せるはずだった値が run_log と監視エンドポイントへ残る。
      return "#{error_class_of(message)} (masking failed: #{e.class})"
    end

    # マスクに失敗したとき、せめて例外クラス名だけは残す。⚠ 診断の手掛かりが
    # ゼロになると「マスクが壊れている」ことにも気付けない。
    def self.error_class_of(message)
      return message.to_s.split(':', 2).first.to_s
    end

    def self.included(base)
      base.extend(Methods)
    end

    module Methods
      def logger
        return Logger.new
      end

      def config
        return Config.instance
      end
    end
  end
end
