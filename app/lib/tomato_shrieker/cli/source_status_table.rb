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

    def self.sort(rows, name)
      key = SORTS[name]
      return rows.sort_by {|v| [key.call(v[:status]), v[:status][:id]]}
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
        row[:problems].any? ? row[:problems].join(',') : '-',
      ]
    end

    def self.format_time(time)
      return time.localtime.strftime('%Y-%m-%d %H:%M:%S')
    end
  end
end
