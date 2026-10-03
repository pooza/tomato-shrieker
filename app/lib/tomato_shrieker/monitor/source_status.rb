module TomatoShrieker
  # 1 ソースぶんの監視状態を組み立てる。`/status.json` の `sources[]` の 1 行 (#1561)。
  #
  # 🔴 **`/status.json` と `bin/shrieker source status` の両方がここを通る。**⚠ 2 つの
  # 出口が同名フィールドで違う数字を出す不具合は `last_attempted_count`（4.8.0）と
  # しきい値の実効値（#1558）で 2 回直した型なので、**計算を出口ごとに書かない**。
  class SourceStatus
    def self.build(source)
      return new(source).to_h
    end

    # 🔴🔴 **緩和を効かせてよい失敗かを見てから、しきい値を決める (#1558)。**
    #
    # ⚠⚠ **エントリを読んだ後に落ちた失敗は 1 回で赤にする。**緩めるとそのぶんの
    # エントリが**恒久的に失われる**（`Entry.insert` は配信より先・unique 制約で
    # 再取得されない）のに、`undelivered` / `stale` / `silent` のどれも立たないので
    # **`error_streak` が唯一のゲート**になっている（#1473）。
    #
    # 📌 緩められるのは「エントリを 1 件も読めていない失敗」＝フィード取得そのものの
    # 失敗だけ。#1558 の動機である YouTube の 404 はこちら。
    # ⚠ `/healthz/source/:id` の判定もこれを使う。
    def self.effective_error_streak_threshold(source, logs)
      return 1 if SourceRunLog.entry_level_error?(logs)
      return source.monitor_error_streak_threshold
    end

    # `/healthz/source/:id` の判定材料 (#1561 で MonitorApp から移した)。
    #
    # 🔴 **`source status --problems` もこれで「緑でない」を決める。**判定を出口ごとに
    # 書くと、Kuma が赤いのに CLI は緑と言う（またはその逆の）食い違いが生まれる。
    def self.checks(source, latest)
      next_run = source.next_run_at(latest.executed_at)
      # 連続エラーで判定する (#1457)。何回で倒すかは error_streak_threshold で調整する。
      # ⚠ **しきい値はソース単位で上書きできる (#1558)。**読む行数もそれに従わせないと、
      # しきい値だけ大きくしても窓が足りず、到達し得ないまま健全扱いになる。
      logs = SourceRunLog.recent_for(
        source.id, SourceRunLog.streak_window(source.monitor_error_streak_threshold)
      )
      streak = SourceRunLog.error_streak_of(logs)
      threshold = effective_error_streak_threshold(source, logs)
      return {
        next_run:,
        stale: Time.now > next_run + source.monitor_grace_seconds,
        streak:,
        threshold:,
        # 🔴 **しきい値を決めたのと同じ述語を持ち回る (#1615 の Codex P2)。**
        # ⚠⚠ **直近の行だけを見て本文に出すと嘘になる。**エントリ処理段の失敗の後に
        # 取得段の失敗が来ると `error_streak: 2 / 1` なのに `entry_stage: false` と
        # 出て、**しきい値が 1 に倒れた理由が読めなくなる**。
        entry_stage: SourceRunLog.entry_level_error?(logs),
        errored: streak >= threshold,
        silent: source.silent?,
        # 試みたのに届かなかった宛先がある (#1504)。取りこぼしは再送されないので、
        # 次に全宛先へ届くか、運用者が確認するまで解除しない (#1506)。
        # ⚠ opt-in の silent? と違い、しきい値の設定なしに常時有効。
        # 判定は Source 側に寄せてある。
        undelivered: (source.undelivered_log if source.undelivered?),
      }
    end

    # `checks` のうち立っているものの名前。空なら健全。
    def self.problems_of(checks)
      return [:stale, :errored, :silent, :undelivered].select {|key| checks[key]}
    end

    # 1 ソースの「緑でない理由」。空なら `/healthz/source/:id` は 200 を返す。
    #
    # ⚠ **順序と分岐は `MonitorApp#build_healthz_source` と同じ。**無効・監視対象外は
    # 意図して止めているので問題にしない (#1503)。宛先ゼロと未実行は checks を
    # 見るまでもなく 503 になる。
    def self.problems(source)
      return [] if source.disable? || !source.monitored?
      return [:no_dest] unless source.dest?
      latest = SourceRunLog.latest_for(source.id)
      return [:no_run] unless latest
      return problems_of(checks(source, latest))
    end

    def initialize(source)
      @source = source
    end

    def to_h
      latest = SourceRunLog.latest_for(@source.id)
      next_run = (@source.next_run_at(latest.executed_at) if @source.monitored? && latest)
      return {
        id: @source.id,
        class: @source.class.to_s,
        schedule: @source.schedule_spec,
        grace_seconds: @source.monitor_grace_seconds,
        last_run_at: latest&.executed_at&.iso8601,
        next_run_at: next_run&.iso8601,
        last_status: latest&.status,
        last_error: latest&.error_message,
        last_duration_ms: latest&.duration_ms,
      }.merge(delivery_status)
    end

    private

    # #1433 (統計) と #1470 (サイレント不発) の指標。
    def delivery_status
      attempted = SourceRunLog.last_attempted(@source.id)
      # 🔴 **窓もしきい値も /healthz/source/:id と完全に同じものを使う（Codex P2・#1558）。**
      # 既定の窓はグローバルのしきい値しか見ないので、ソース側で sample_size (50) を
      # 超える値に上書きすると **503 にしている当人が `error_streak: 50 / 100` という
      # 自己矛盾した数字を出す**。⚠⚠ **しきい値も「宣言値」ではなく実効値を出す。**
      # `effective_error_streak_threshold` が 1 に倒している場合、宣言値を出すと
      # `/healthz` が `1 / 1` で 503 なのに `/status.json` は `4` と言う。
      # ⚠ **2 つのエンドポイントが同名フィールドで違う数字を出す**のは 4.8.0 の
      # レビューで `last_attempted_count` で潰した型の不具合なので、繰り返さない。
      logs = SourceRunLog.recent_for(
        @source.id, SourceRunLog.streak_window(@source.monitor_error_streak_threshold)
      )
      return SourceRunLog.summary_of(logs).merge(
        dest_count: @source.dest_count,
        # #1504: 直近の配信試行の内訳。undelivered が true なら未解決の取りこぼしがある
        last_attempted_at: attempted&.executed_at&.iso8601,
        # ⚠ 確認済みなら false になる (#1506)。なぜ緑なのかは silence_acknowledged_at で読む
        undelivered: @source.undelivered?,
        # 🔴 **`attempted` から出す（4.8.0 リリース前レビュー）。**`latest` は
        # **直近の run** なので、no-op を挟むと **`last_attempted_at` は前の試行を
        # 指しているのに件数だけ 0** という自己矛盾になる。⚠ 本番で再現した:
        # `capsicum` が `/status.json` で 0/0、同じ行が DB では 1/1。
        # ⚠ `/healthz/source/:id` の 503 本文は `attempted` 側から出しているので、
        # **2 つのエンドポイントが同名フィールドで違う数字**を出していた。
        last_attempted_count: attempted&.attempted_count,
        last_delivered_count: attempted&.delivered_count,
        last_delivered_at: @source.last_delivered_at&.iso8601,
        last_delivered_at_origin: @source.last_delivered_at_origin,
        silence_tolerance_seconds: @source.monitor_silence_tolerance_seconds,
        # 🔴 **3 値 (#1502)。**`null` は「まだ判定できない」＝ run_log 上に配信実績も
        # 確認記録も無く、観測開始からしきい値も経っていない。⚠ 以前は `false` が
        # 「健全」と「判定不能」を兼ねていて、外から区別できなかった。
        silent: @source.silent?,
        # なぜその判定なのか。`observation` なら下限（観測開始からの経過）に頼っている
        silence_baseline: @source.silence_baseline&.iso8601,
        silence_baseline_origin: @source.silence_baseline_origin,
        # #1505: 「なぜ緑なのか」を答えられるようにする。確認済みなら silent は
        # false だが、それは健全だからではなく運用者が確認したから
        silence_acknowledged_at: SilenceAck.acknowledged_at(@source.id)&.iso8601,
        error_rate_24h: SourceRunLog.error_rate(@source.id),
        # #1558: 「なぜこのソースはまだ緑なのか」を外から説明できるようにする
        error_streak_threshold: self.class.effective_error_streak_threshold(@source, logs),
      )
    end
  end
end
