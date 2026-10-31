module TomatoShrieker
  # 配信へ進む前に失ったエントリの判定 (#1574)。`SourceRunLog` に混ぜる。
  module SourceRunLogLoss
    # ⚠ 種別の正本は書く側の定数（`FeedSource` / `Source`）。
    LOSS_KINDS = [FeedSource::ENTRY_FAILURE_KIND, Source::EXEC_FAILURE_KIND].freeze

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
    # `record_failure` を通らずに `exec_with_run_log` の rescue へ入る。⚠ **4.14.0 までは、
    # それが「段は立っているのに `shrieker_errors` が空の error 行」になった**（下の
    # `aborted_in_entry_stage?`）。4.15.0 からは rescue が `source#exec` を 1 件数えるので、
    # `lost_entry_count` の側で立つ。⚠⚠ どちらの形も数えないと、**次の run で連続エラーが
    # 切れた時点で緑に戻る**うえ、その行が「直近の段に入った run」になって**前の取りこぼしの
    # 警告まで消す**。
    def lost_entries?
      return false unless entry_stage == true
      return lost_entry_count.positive? || aborted_in_entry_stage?
    end

    # 段に入った後、内訳を 1 件も残さずに落ちた run。⚠ 失った件数は分からない。
    # ⚠ **この形になるのは 4.14.0 までに書かれた行だけ。**4.15.0 からは `Source#record_exec_abort`
    # が `source#exec` を 1 件数えるので、`lost_entry_count` の側で立つ（宛先の失敗と混ざっても）。
    def aborted_in_entry_stage?
      return entry_stage == true && error? && shrieker_error_counts.empty?
    end

    # 恒久的に失ったエントリの件数。⚠ **種別で数える（#1685 の Codex P2）。**
    #
    # - `source#entry`: 保存の後で落ちたエントリ（`FeedSource`）
    # - `source#exec`: エントリ処理の途中で run ごと落ちた（件数は不明なので 1 と数える）
    #
    # ⚠ **`source#fetch` は数えない。**保存の前（解析）で落ちたエントリで、行が無いので次の
    # run が拾い直す。数えると、直らない 1 件のせいで「失っていないのに赤」が続く。
    # ⚠ 宛先の失敗（Shrieker のクラス名のキー）も数えない。あちらは `undelivered?`。
    def lost_entry_count
      return shrieker_error_counts.slice(*LOSS_KINDS).values.sum(&:to_i)
    end

    module ClassMethods
      # 直近の「エントリ処理段に入った run」(#1574)。⚠ 新着の無い run は段に入らないので、
      # 取りこぼしは次に新着を処理する run が来るまで（または運用者が確認するまで）残る。
      # ⚠ 根拠行は prune から守る（`last_entry_stage_ids`・#1687）。
      def last_entry_stage(source_id)
        logs = where(source_id:, entry_stage: true)
        return logs.order(Sequel.desc(:executed_at), Sequel.desc(:id)).first
      end
    end
  end
end
