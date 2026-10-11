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
    #
    # 🔴 **run ごと例外で抜けた形も数える（#1685 の Codex P1）。**`CommandSource` /
    # `IcalendarSource` は、エントリを読んだ後（`create_template` など）で落ちると
    # `record_failure` を通らずに `exec_with_run_log` の rescue へ入るので、**段は立って
    # いるのに `shrieker_errors` が空の error 行**になる。⚠⚠ 件数だけで判定すると 0 件＝
    # 「失っていない」と読み、**次の run で連続エラーが切れた時点で緑に戻る**うえ、
    # その行が「直近の段に入った run」になって**前の取りこぼしの警告まで消す**。
    def lost_entries?
      return false unless entry_stage == true
      return lost_entry_count.positive? || aborted_in_entry_stage?
    end

    # 段に入った後、内訳を 1 件も残さずに落ちた run。⚠ 失った件数は分からない。
    def aborted_in_entry_stage?
      return entry_stage == true && error? && shrieker_error_counts.empty?
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
