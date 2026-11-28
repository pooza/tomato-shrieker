module TomatoShrieker
  class Environment < Ginseng::Environment
    include Package

    def self.dir
      return TomatoShrieker.dir
    end

    def self.dsn
      return "sqlite://#{db}"
    end

    # DB への接続はここを通す（#1806）。
    #
    # 🔴 **待ちは `busy_handler_timeout` で持つ。**Sequel が既定で掛ける `busy_timeout`（と
    # `PRAGMA busy_timeout`）は SQLite の C 側で眠るので、**GVL を握ったまま待つ**。daemon の中で
    # 錠を持つ側のスレッドが進めず、待つ側が 5 秒で BUSY になる（4.21.0 リリース前レビュー・
    # 手元の混在負荷で心拍の最大間隔 5.02 秒 → 0.21 秒）。`busy_handler_timeout=` は Ruby 側で
    # 眠るので GVL を手放す。⚠ handler を置き換えるので、`PRAGMA busy_timeout` を後から掛けない。
    # ⚠ `after_connect` は接続ごとに走る（プールが増やした接続にも効く）。
    def self.connect_database(url = dsn)
      return Sequel.connect(url, after_connect: ->(conn) {conn.busy_handler_timeout = 5000})
    end

    def self.rake?
      return ENV['RAKE'].present? && !test? rescue false
    end

    # ginseng-upstream: no — 文字列で返し、`RACK_ENV` を見ない。tomato では子プロセスへ渡す `RACK_ENV` の
    # 元（`CommandRunner#command`）なので、上流のように `RACK_ENV` を読むと循環し、Symbol は spawn の env に渡せない。
    # 📌 `name` / `test?` / `development?` / `production?` は上流と同じだったので消した（#1786）。
    def self.type
      return config['/environment'] || 'development'
    end

    # ランタイムの能力欠落を可視化する (#1471)。
    #
    # 🔴 **YJIT は Rust の無い環境ではビルド時に黙って外れる。** エラーにならない
    # まま「YJIT 抜きの Ruby」が完成し、バイトコード実行が 24〜25% 遅いサーバーが
    # 出来上がる（モロヘイヤでの実測 / pooza/chubo2#69）。
    #
    # `Ginseng::Environment.jit?` は `defined?(RubyVM::YJIT)` ＝**ビルドに含まれて
    # いるか**しか見ないので、`RubyVM::YJIT.enable if Environment.jit?` は
    # 「入っていれば有効、入っていなければ黙って無効」になる。⚠ **後者になっても
    # 誰も気づけない**のが問題。実例: ダイスキー staging (dev27) は rustup 導入済み
    # なのに Ruby 4.0.6 が YJIT 抜きでビルドされていた（pooza/chubo2#123）。
    #
    # ⚠ **運用の関心は `yjit_available`（積まれているか）ではなく
    # `yjit_enabled`（実際に効いているか）。**
    #
    # ⚠ **ここでは異常判定をしない。** 能力の欠落は障害ではなく、`/healthz` が
    # 503 になるとサーバーが「停止」扱いになる。検知したい場合は Kuma の
    # キーワード監視で `"yjit_enabled": true` を見る。
    def self.ruby_health
      return {
        version: RUBY_VERSION,
        # ⚠ `Ginseng::Environment.jit?` は `defined?(RubyVM::YJIT)` の戻りを
        # そのまま返すので、真のとき **`"constant"`（String）** になる。JSON に
        # 素で載せると boolean にならないので、ここで真偽へ倒す。
        yjit_available: !jit?.nil?,
        yjit_enabled: yjit_enabled?,
      }
    end

    # ⚠ `jit?` は「ビルドに入っているか」。こちらは「いま効いているか」。
    def self.yjit_enabled?
      return false unless jit?
      return RubyVM::YJIT.enabled? == true
    end

    def self.db
      return File.join(
        dir,
        'tmp/db',
        config['/sqlite3/db'],
      )
    end
  end
end
