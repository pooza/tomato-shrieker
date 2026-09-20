require 'sequel/model'

module TomatoShrieker
  class SourceRunLog < Sequel::Model(:source_run_log)
    include Package

    STATUS_SUCCESS = 'success'.freeze
    # 配信できたものと失敗したものが混在した run (#1482)。
    # error と分けるのは「99 件配信できた run」と「全滅した run」を status の上で
    # 区別するため。error_streak は倒さないので、部分失敗では healthz を赤にしない。
    STATUS_PARTIAL = 'partial'.freeze
    STATUS_ERROR = 'error'.freeze

    dataset_module do
      def latest_for(source_id)
        return where(source_id:).order(Sequel.desc(:executed_at)).first
      end

      def recent_for(source_id, limit)
        return where(source_id:).order(Sequel.desc(:executed_at), Sequel.desc(:id)).limit(limit).all
      end
    end

    # 保存時に正規化していても、それ以前に書かれた行には ASCII-8BIT が残っている (#1469)。
    # 読み出し側でも倒しておかないと、既存行を読んだ瞬間に監視の JSON が壊れる。
    def error_message
      return super&.to_utf8
    end

    # run が終わった時刻 (#1506 の Codex P2)。
    #
    # ⚠⚠ **`executed_at` は run の「開始」時刻**（`record` が `started_at` を書く）。
    # 確認 (ack) との前後を開始時刻で比べると、**ack の直前に始まって直後に未達で
    # 終わった run を「確認済み」として消してしまう**。本番の最長 run は 62.6 秒
    # （2026-09-05 実測・60 秒級が 5 本）あるので、窓は微小ではない。
    def finished_at
      return executed_at + (duration_ms.to_i / 1000.0)
    end

    def error?
      return status == STATUS_ERROR
    end

    def partial?
      return status == STATUS_PARTIAL
    end

    # 🔴 **エントリ処理段まで進んでいた run か (#1586)。**
    #
    # ⚠⚠ **旧行は `entry_stage` が NULL。**migration 013 より前に書かれた行に
    # 遡って段は入れられないので、**NULL の行だけ従来の代理**
    # （`shrieker_errors` が空でない ＝ FeedSource でだけ成立していた見分け）
    # へ倒す。⚠ ここを「NULL ＝ エントリ処理段」にすると、**デプロイ直後に
    # 緩和を掛けている 5 ソースが一斉に 503** になる（migration 010 の
    # backfill で踏んだのと同じ型）。
    def entry_stage_error?
      return entry_stage unless entry_stage.nil?
      return shrieker_error_counts.present?
    end

    # 配信を 1 件も試みずに完走した run。#1457 の「no-op run」。
    # run 自体が失敗した場合は試行ゼロでも no-op ではない。
    def noop?
      return false unless status == STATUS_SUCCESS
      return attempted_count.to_i.zero?
    end

    def delivered?
      return delivered_count.to_i.positive?
    end

    # 配信を試みた run。no-op run と区別する。
    def attempted?
      return attempted_count.to_i.positive?
    end

    # 試みたのに届かなかった宛先がある run (#1504)。
    # 宛先ごとの識別子を持たなくても、試行数と成功数の差で「取りこぼし」は判る。
    def undelivered?
      return false unless attempted?
      return delivered_count.to_i < attempted_count.to_i
    end

    def shrieker_error_counts
      return {} if shrieker_errors.blank?
      parsed = JSON.parse(shrieker_errors)
      return parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      return {}
    end

    def self.record_success(source_id, started_at:, stats: nil)
      return record(source_id, started_at:, status: STATUS_SUCCESS, stats:)
    end

    # 配信できたものと失敗したものが混在した run (#1482)。
    # error_message は残す。status が error でないだけで、失敗は失敗として読めるようにする。
    def self.record_partial(source_id, started_at:, error:, stats: nil)
      return record(source_id, started_at:, status: STATUS_PARTIAL, error:, stats:)
    end

    def self.record_error(source_id, started_at:, error:, stats: nil)
      return record(source_id, started_at:, status: STATUS_ERROR, error:, stats:)
    end

    def self.record(source_id, started_at:, status:, error: nil, stats: nil)
      create({
        source_id:,
        executed_at: started_at,
        status:,
        error_message: Package.error_message(error),
        duration_ms: duration_ms(started_at),
      }.merge(stats_columns(stats)))
    rescue => e
      Sentry.capture_exception(e) if Sentry.initialized?
    end

    def self.stats_columns(stats)
      return {} unless stats
      errors = stats.shrieker_errors
      return {
        attempted_count: stats.attempted_count,
        delivered_count: stats.delivered_count,
        shrieker_errors: errors.empty? ? nil : JSON.dump(errors),
        entry_stage: stats.entry_stage?,
      }
    end

    def self.prune(retention_days)
      cutoff = retention_cutoff(retention_days)
      count = where(Sequel.lit('executed_at < ?', cutoff))
        .exclude(id: last_delivered_ids).exclude(id: first_run_ids)
        .exclude(id: last_attempted_ids).delete
      redact_expired(cutoff)
      return count
    end

    # 🔴 **retention を過ぎても残す保護行から error_message を落とす (#1511)。**
    #
    # 保護行は 3 系統に増え、**ソースあたり最大 3 行が retention_days を超えて
    # 無期限に残る**ようになった。⚠ とくに `last_attempted_ids` が守る行は
    # 「直近の配信試行」＝ `partial` / `error` で `error_message` を持つ可能性が
    # 最も高い。`/monitor/retention_days` が担保していた「例外メッセージは
    # N 日で消える」という上限が、保護行だけ外れていた。
    #
    # ⚠ **削除の後に呼ぶこと。** 保護されていない期限切れ行は先に消えているので、
    # ここで残っている期限切れ行は保護行だけになる。
    #
    # ⚠ 判定に使うのは `executed_at` / `attempted_count` / `delivered_count` だけ
    # なので、`error_message` を落としても保護の意味は失われない。
    def self.redact_expired(cutoff)
      return where(Sequel.lit('executed_at < ?', cutoff))
          .exclude(error_message: nil).update(error_message: nil)
    end

    # 「最後に配信できた時刻」の根拠行はソースごとに 1 行だけ prune から守る。
    # 刈ってしまうと沈黙が retention_days を超えた瞬間に last_delivered_at が nil に化け、
    # 長期の沈黙ほど検知できなくなる (#1470)。
    def self.last_delivered_ids
      return where(Sequel.lit('delivered_count > 0')).group(:source_id)
          .select(Sequel.function(:max, :id))
    end

    # 「いつから観測しているか」の根拠行もソースごとに 1 行だけ守る (#1483)。
    # 未配信のソースは last_delivered_ids に引っかからないので、これが無いと
    # observed_since が常に retention_days 前に張り付き、それより長い
    # silence_tolerance が永久に成立しない。
    def self.first_run_ids
      return group(:source_id).select(Sequel.function(:min, :id))
    end

    # 「直近の配信試行」の根拠行もソースごとに 1 行だけ守る (#1504)。
    # ⚠ これを刈ると、取りこぼしを検知して赤くなったソースが retention_days の経過だけで
    # 黙って緑に戻る。**次に配信できたときだけ解除する**という仕様が壊れる。
    def self.last_attempted_ids
      return where(Sequel.lit('attempted_count > 0')).group(:source_id)
          .select(Sequel.function(:max, :id))
    end

    def self.duration_ms(started_at)
      return ((Time.now - started_at) * 1000).to_i
    end

    # 実際に配信できた最後の時刻。last_delivered_ids が根拠行を prune から守るので、
    # 一度でも配信していれば消えない (#1470)。
    def self.last_delivered_at(source_id)
      row = where(source_id:).where(Sequel.lit('delivered_count > 0'))
        .order(Sequel.desc(:executed_at)).first
      return row&.executed_at
    end

    # 直近の「配信を試みた run」(#1504)。
    #
    # ⚠ no-op run (新着が無く配信ゼロで完走した run) は読み飛ばす。**新着が無いことは
    # 失敗の解消にならない。**取りこぼしたエントリは `Entry.insert` が配信より先に走る
    # ため再送されず (`entry.tooted` 列も migration/004 で削除済み)、永久に失われている。
    # no-op で緑に戻すと、宛先が死んだまま監視だけが健全に見える。
    def self.last_attempted(source_id)
      return where(source_id:).where(Sequel.lit('attempted_count > 0'))
          .order(Sequel.desc(:executed_at), Sequel.desc(:id)).first
    end

    # 試みたのに届かなかった配信が未解決のまま残っているか (#1504)。
    #
    # 🔴 2026-06 の Matrix 配信停止 (#1455) がこの形だった。hooks が 2 つあり
    # matrix-webhook だけ毎回失敗、モロヘイヤは成功。`delivered_count > 0` なので
    # status は `partial`、`last_delivered_at` も前進し続け、error_streak も silent も
    # 立たず、監視は最後まで緑だった。
    def self.undelivered?(source_id)
      return last_attempted(source_id)&.undelivered? || false
    end

    # このソースの run を観測し始めた時刻 (#1483)。
    # 一度も配信していないソースでは、ここからの経過が無配信期間の下限になる。
    # first_run_ids が根拠行を prune から守るので retention_days では消えない。
    def self.observed_since(source_id)
      row = where(source_id:).order(:executed_at, :id).first
      return row&.executed_at
    end

    # 直近 N 件から求まる指標をまとめて返す。
    # /status.json は全ソース分を 1 リクエストで返すので、
    # 指標ごとに recent_for を呼ぶとソース数 × 指標数のクエリになる。ここで 1 回に畳む。
    # ⚠⚠ **streak だけ広い窓で読み、他の指標は sample_size で切る (#1558)。**
    # しきい値をソース単位で `sample_size` より大きくすると窓が広がるが、
    # **`noop_streak` / `duration_ms` / `shrieker_errors` まで一緒に広げてはいけない。**
    # `/monitor/sample_size` の「統計の算出に使う直近 run 件数」という定義に反し、
    # 🔴 **503 本文（`sample_size` 固定）と `/status.json` が同名フィールドで違う数字**
    # を出す。4.8.0 で `last_attempted_count` で潰したのと同じ型の不具合。
    # ⚠ 追加のクエリは打たない（`logs` を切るだけ）。#1472 の約 900ms を増やさない。
    def self.summary_for(source_id, limit: streak_window)
      return summary_of(recent_for(source_id, limit))
    end

    # 取得済みの logs から出す版。⚠ **呼び出し側が logs を別の用途にも使うとき**
    # （`entry_level_error?` の判定等）に、同じ行を 2 回引かないため (#1558)。
    def self.summary_of(logs)
      sample = logs.first(sample_size)
      return {
        error_streak: error_streak_of(logs),
        noop_streak: noop_streak_of(sample),
        duration_ms: duration_stats_of(sample),
        shrieker_errors: shrieker_error_distribution_of(sample),
      }
    end

    # 連続エラー回数 (#1457)。
    #
    # no-op run (新着が無く配信ゼロで完走した run) は「エラーでない」＝ run が最後まで
    # 走った証拠なので streak を切る。ここを読み飛ばすと、配信のたびにしか streak が
    # 戻らなくなり、新着の少ないソースが一過性エラー 1 回で 503 に貼り付く。
    # 「単発で倒さない」は error_streak_threshold で調整する。
    def self.error_streak(source_id, limit: streak_window)
      return error_streak_of(recent_for(source_id, limit))
    end

    # 🔴🔴 **しきい値の緩和を効かせてよい失敗か (#1558)。**
    #
    # ⚠⚠ **エントリを読んだ後に落ちた失敗は、1 回で赤にしないとエントリを失う。**
    # `Entry.insert` は配信より先に走るので、`create_record` / `create_template` /
    # `enclosures` / `Entry#shriek` 以降で落ちた run のエントリは**unique 制約で
    # 二度と取得されず恒久的に失われる**。しかもその失敗は `record_failure` 経由で
    # `attempted_count` に載らないため、**`undelivered?` も `stale` も `silent` も
    # 立たない**＝ `error_streak` が唯一のゲート（#1473 / DeliveryStats のコメント）。
    #
    # 🔴🔴 **段は run_log の `entry_stage` が直接持つ (#1586)。**
    #
    # ⚠⚠ **4.9.0 までは `shrieker_errors` が空であることを「取得段の失敗」の代理に
    # していたが、その代理が成立するのは FeedSource だけだった。**
    # `CommandSource#exec` / `IcalendarSource#exec` は `create_template` で落ちると
    # `@delivery_stats` が空のまま `exec_with_run_log` の rescue に入り、
    # **`shrieker_errors` が空の error 行**になる。＝ **エントリ処理段の失敗が
    # 「取得段の失敗」と誤読され、緩めたしきい値がそのまま残っていた**
    # （#1583 の Codex P1）。⚠ 代理をやめて事実を書く、という差分。
    #
    # 📌 **緩和が効いてよいのは取得段だけ**（#1558 の動機である YouTube の 404 は
    # `entries` の評価中に抜けるので、そもそも段が立たない）。
    #
    # ⚠ **仕様は 1 行で言える: 「しきい値を緩められるのは、エントリを 1 件も
    # 読めていない失敗だけ」。**取得が不安定な相手は許容するが、取りこぼしは許容しない。
    def self.entry_level_error?(logs, cutoff = retention_cutoff)
      return streak_logs(logs, cutoff).any?(&:entry_stage_error?)
    end

    # 🔴 **retention の cutoff より古い行で streak を止める (#1608)。**
    #
    # ⚠⚠ `prune` は retention を過ぎた行を消すとき、ソースごとに 3 行
    # （`first_run_ids` / `last_attempted_ids` / `last_delivered_ids`）を**無期限に守る**。
    # **疎なソース**では retention 内の行が `limit` より少ないので、**守られた古い行が
    # そのまま末尾に並ぶ**。間にあった成功行は prune で消えているので、
    # **「直近のエラー」と「何か月も前の最初の run のエラー」が連続して見え、streak が
    # 水増しされる**。
    #
    # 例: `0 0 1,2 * *`・retention 14 日・最初の run が error。その後ずっと成功していても、
    # 今月の 1 日・2 日が error になると **streak = 3** になり、**実際には連続していない
    # 失敗で `/healthz/source/:id` が 503 を立てる**。
    #
    # ⚠ 守られた行は `last_delivered_at` / `observed_since` の**根拠行**であって、
    # **連続性の根拠ではない**。
    # ⚠ `source validate` のしきい値到達性 WARN (#1587 / #1594) は retention の窓だけで
    # 数えるので、ここを揃えないと**警告と実際の判定がずれる**。
    def self.error_streak_of(logs, cutoff = retention_cutoff)
      return streak_logs(logs, cutoff).size
    end

    # 🔴🔴 **「いま連続している失敗」の実体 (#1613 の Codex P1)。**
    #
    # ⚠⚠ **streak の本数と、しきい値の緩和判定は同じ範囲を見なければならない。**
    # 片方だけ cutoff で切ると、**streak からは除いた保護行を
    # `entry_level_error?` が拾い、緩和だけ潰れて 503 が立つ**
    # （＝ この修正が無視したかった「連続していない過去の失敗」で赤くなる）。
    def self.streak_logs(logs, cutoff = retention_cutoff)
      return logs.take_while {|log| log.executed_at >= cutoff && log.error?}
    end

    # 何も配信しないまま連続した run の回数 (#1470)。
    # エラーで終わった run も「配信できていない」ので数に入れる。
    def self.noop_streak(source_id, limit: sample_size)
      return noop_streak_of(recent_for(source_id, limit))
    end

    def self.noop_streak_of(logs)
      streak = 0
      logs.each do |log|
        break if log.delivered?
        streak += 1
      end
      return streak
    end

    def self.duration_stats(source_id, limit: sample_size)
      return duration_stats_of(recent_for(source_id, limit))
    end

    def self.duration_stats_of(logs)
      values = logs.filter_map(&:duration_ms).sort
      return nil if values.empty?
      return {
        min: values.first,
        avg: (values.sum.to_f / values.size).round,
        max: values.last,
        p95: values[percentile_index(values.size, 95)],
      }
    end

    def self.percentile_index(size, percentile)
      index = ((size * percentile) / 100.0).ceil - 1
      return index.clamp(0, size - 1)
    end

    def self.error_rate(source_id, hours: 24)
      since = Time.now - (hours * 3600)
      logs = where(source_id:).where(Sequel.lit('executed_at >= ?', since)).all
      return nil if logs.empty?
      return (logs.count(&:error?).to_f / logs.size).round(3)
    end

    # 直近 N 件の shrieker 別エラー件数 (#1433)。
    def self.shrieker_error_distribution(source_id, limit: sample_size)
      return shrieker_error_distribution_of(recent_for(source_id, limit))
    end

    def self.shrieker_error_distribution_of(logs)
      distribution = Hash.new(0)
      logs.each do |log|
        log.shrieker_error_counts.each {|klass, count| distribution[klass] += count.to_i}
      end
      return distribution
    end

    def self.sample_size
      return Config.instance['/monitor/sample_size']
    end

    # prune の境界と streak の境界を 1 本にする (#1608)。
    # ⚠ **同じ値から出すこと。**別々に計算すると「消える行」と「数える行」がずれる。
    def self.retention_cutoff(days = Config.instance['/monitor/retention_days'])
      return Time.now - (days * 86_400)
    end

    # error_streak_threshold が sample_size より大きいと、読む行数が足りず
    # しきい値に到達し得ない＝どれだけ連続で失敗しても健全のままになる。
    #
    # ⚠ **しきい値はソース単位で上書きできる (#1558)。**呼び出し側が解決した値を
    # 渡す。⚠ 省略時はグローバル値で、ソースを持たない呼び出し（prune 等）向け。
    def self.streak_window(threshold = nil)
      threshold ||= Config.instance['/monitor/error_streak_threshold']
      return [sample_size, threshold].max
    end
  end
end
