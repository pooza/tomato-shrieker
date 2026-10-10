module TomatoShrieker
  # 直近 N 時間に**同じ秒に発火したソースの群** (#1561)。`bin/shrieker source collisions` が使う。
  #
  # ⚠ **定義ではなく実績から見る。**`every` の位相は起動時刻で決まるので、
  # 定義を突き合わせても同時発火は分からない。`executed_at` は run の開始時刻＝発火時刻。
  # 📌 同じ顔ぶれは 1 行にまとめ、何回重なったかを `count` に数える。
  module SourceCollisions
    def self.find(hours: 24)
      since = Time.now - (hours * 3600)
      rows = SourceRunLog.where(Sequel.lit('executed_at >= ?', since))
        .select_map([:source_id, :executed_at])
      return summarize(per_second(rows))
    end

    # 秒ごとに束ね、2 ソース以上が居合わせた秒だけ `[ids, 最後の発火時刻]` で返す。
    # ⚠ 同じソースが同じ秒に 2 本走っても衝突ではない。
    def self.per_second(rows)
      return rows.group_by {|_, at| at.to_i}.filter_map do |_, v|
        ids = v.map(&:first).uniq.sort
        [ids, v.map(&:last).max] if ids.size > 1
      end
    end

    def self.summarize(seconds)
      groups = seconds.group_by(&:first).map do |ids, v|
        {source_ids: ids, count: v.size, last_at: v.map(&:last).max}
      end
      return groups.sort_by {|v| [-v[:count], -v[:source_ids].size, v[:source_ids]]}
    end
  end
end
