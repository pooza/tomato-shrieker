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
      return "#{error.class}: #{error.message}".to_utf8
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
