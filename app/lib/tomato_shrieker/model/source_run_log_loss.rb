module TomatoShrieker
  # 配信へ進む前に失ったエントリの判定 (#1574)。`SourceRunLog` に混ぜる。
  module SourceRunLogLoss
    def self.included(base)
      base.extend(ClassMethods)
    end

    # 🔴 **配信へ進む前にエントリを失った run か (#1574)。**
    #
    # `record_failure`（宛先に触れる前の失敗）は `attempted_count` に載らないので、
    # 他のエントリが 1 件でも届くと run は `partial`・`attempted == delivered` になり、
    # **`undelivered?` も `error_streak` も立たない**。⚠⚠ それでも `Entry.insert` は済んで
    # いるので、落ちたエントリは unique 制約で二度と取得されない＝恒久的に失われている。
    #
    # ⚠ **`undelivered?` には混ぜない。**あちらは「宛先に届かなかった」で、こちらは宛先が
    # 健全でも起きる。混ぜると運用者は存在しない宛先障害を探しに行く（docs/monitoring.md）。
    # ⚠ **段に入っていない run は数えない。**エントリを 1 件も読めていないなら失うものが無い。
    # ⚠ 旧行（`entry_stage` が NULL・migration 013 より前）も数えない＝デプロイで赤くしない。
    def lost_entries?
      return false unless entry_stage == true
      return lost_entry_count.positive?
    end

    # 宛先に触れる前に落ちた件数。⚠ 専用の列は無いので、失敗の総数から「試みて届かなかった
    # ぶん」を引いて出す（`shrieker_errors` は両方を数え、`attempted - delivered` は後者だけ）。
    def lost_entry_count
      attempted_failures = attempted_count.to_i - delivered_count.to_i
      return [shrieker_error_counts.values.sum(&:to_i) - attempted_failures, 0].max
    end

    module ClassMethods
      # 直近の「エントリ処理段に入った run」(#1574)。⚠ 新着の無い run は段に入らないので、
      # 取りこぼしは次に新着を処理する run が来るまで（または運用者が確認するまで）残る。
      # ⚠ **prune の保護行にはしていない。**確認しないまま保持期間を過ぎると行ごと消える。
      def last_entry_stage(source_id)
        return where(source_id:, entry_stage: true)
            .order(Sequel.desc(:executed_at), Sequel.desc(:id)).first
      end
    end
  end
end
