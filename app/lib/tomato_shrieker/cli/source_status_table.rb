require 'time'

module TomatoShrieker
  # `bin/shrieker source status` の表 (#1561)。
  #
  # ⚠ **値は `SourceStatus` が組み立てたものを並べ替え・整形するだけで、ここで計算しない。**
  # 計算を出口ごとに書くと `/status.json` と食い違う。
  module SourceStatusTable
    # `--sort` の並べ替えキー。⚠ 値が無い行は「より疑わしい」側に寄せない。
    # 最終配信が無いソースだけは例外で先頭に来る（一度も届いていない＝いちばん疑わしい）。
    SORTS = {
      'error_rate' => proc {|v| -(v[:error_rate_24h] || -1)},
      'last_delivered' => proc do |v|
        v[:last_delivered_at] ? Time.parse(v[:last_delivered_at]).to_f : 0.0
      end,
      'streak' => proc {|v| -(v[:error_streak] || 0)},
    }.freeze

    HEADER = ['ID', 'CLASS', 'SCHEDULE', 'LAST', 'STREAK', 'ERR24H', 'DELIVERED', 'PROBLEMS'].freeze

    # ⚠ **`--sort` を値なしで渡すと Thor の enum 検査をすり抜ける (#1648)。**
    # 知らないキーは `Thor::Error` にする（nil を `call` して NoMethodError で落ちていた）。
    def self.sort(rows, name)
      key = SORTS.fetch(name) do
        raise Thor::Error, "--sort は #{SORTS.keys.join(' / ')} のいずれかを指定してください。"
      end
      return rows.sort_by {|v| [key.call(v[:status]), v[:status][:id]]}
    end

    # 1 ソースの失敗で全体を落とさない。壊れた側は `build_failed` として見せる
    # （`MonitorApp#source_status` と同じ形の行を返す）。
    def self.row(source)
      status = SourceStatus.build(source)
      # ⚠ **`disabled` は表示用の目印で、`problems` に混ぜない（#1638 の Codex P2）。**
      # 無効ソースの healthz は 200 なので、混ぜると `--problems --all` が 200 のものを出す。
      return {status:, problems: SourceStatus.problems(source), disabled: source.disable?}
    rescue => e
      return {
        status: {id: source.id, class: source.class.to_s, error: Package.error_message(e)},
        # ⚠ **無効・監視対象外は例外の経路でも免除する（#1638 の Codex P2）。**healthz は
        # 組み立てる前にこれらを 200 で返すので、ここで問題にすると食い違う。
        problems: source.disable? || !source.monitored? ? [] : [:build_failed],
        disabled: source.disable?,
      }
    end

    # 組み立てに失敗した行の理由 (#1648)。⚠ 表には `build_failed` としか出ないので、
    # 理由（空の DB に向けたときの `no such table` など）は別に出す。
    def self.failures(rows)
      return rows.filter_map do |v|
        "#{v[:status][:id]}: #{v[:status][:error]}" if v[:status][:error]
      end
    end

    def self.lines(rows)
      return [HEADER] + rows.map {|v| line(v)}
    end

    def self.line(row)
      status = row[:status]
      schedule = status[:schedule]
      return [
        status[:id],
        status[:class].split('::').last,
        schedule ? "#{schedule[:type]} #{schedule[:value]}" : '-',
        status[:last_status] || '-',
        status[:error_streak] ? "#{status[:error_streak]}/#{status[:error_streak_threshold]}" : '-',
        status[:error_rate_24h] ? "#{(status[:error_rate_24h] * 100).round}%" : '-',
        status[:last_delivered_at] ? format_time(Time.parse(status[:last_delivered_at])) : '-',
        marks(row),
      ]
    end

    # 問題に加えて無効の目印も出す。⚠ 目印は `problems` には入れない（`--problems` の判定を汚す）
    def self.marks(row)
      marks = row[:problems] + (row[:disabled] ? [:disabled] : [])
      return marks.any? ? marks.join(',') : '-'
    end

    def self.format_time(time)
      return time.localtime.strftime('%Y-%m-%d %H:%M:%S')
    end
  end
end
