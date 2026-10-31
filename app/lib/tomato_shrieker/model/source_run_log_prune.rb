module TomatoShrieker
  # 保持期間を過ぎた行の削除と、削除から守る行 (#1470)。`SourceRunLog` に混ぜる。
  module SourceRunLogPrune
    def prune(retention_days)
      cutoff = retention_cutoff(retention_days)
      count = where(Sequel.lit('executed_at < ?', cutoff))
        .exclude(id: boundary_run_ids(:min)).exclude(id: boundary_run_ids(:max))
        .exclude(id: last_delivered_ids).exclude(id: last_attempted_ids)
        .exclude(id: last_entry_stage_ids).delete
      redact_expired(cutoff)
      return count
    end

    # 🔴 **retention を過ぎても残す保護行から error_message を落とす (#1511)。**
    #
    # 保護行は 5 系統に増え、**ソースあたり最大 5 行が retention_days を超えて
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
    def redact_expired(cutoff)
      expired = where(Sequel.lit('executed_at < ?', cutoff)).exclude(error_message: nil)
      return expired.update(error_message: nil)
    end

    # 「最後に配信できた時刻」の根拠行はソースごとに 1 行だけ prune から守る。
    # 刈ってしまうと沈黙が retention_days を超えた瞬間に last_delivered_at が nil に化け、
    # 長期の沈黙ほど検知できなくなる (#1470)。
    def last_delivered_ids
      return boundary_run_ids(:max, where(Sequel.lit('delivered_count > 0')))
    end

    # ソースごとの**最古行 (`:min`) と最新行 (`:max`)** を prune から守る。
    #
    # - `:min` ＝ 「いつから観測しているか」の根拠行 (#1483)。未配信のソースは
    #   `last_delivered_ids` に引っかからないので、これが無いと `observed_since` が
    #   常に `retention_days` 前に張り付き、それより長い `silence_tolerance` が
    #   永久に成立しない。
    # - 🔴🔴 `:max` ＝ 「直近の run」の根拠行 (#1621 の Codex P2)。⚠⚠ `streak_logs` は
    #   **先頭行だけ cutoff を免除する**ので、**先頭行が本当に最新の run でなければ
    #   ならない**。no-op success（新着が無く配信ゼロで完走した run）は他の系統の
    #   どれにも掛からないため、これが無いと**疎なソースで「最新の成功 run だけ刈られ、
    #   `:min` が守る古い error が先頭に来る」**＝ **一度直ったソースが永久に赤いまま**になる。
    #
    # 🔴 **ソースごとの端の行を、読む側と同じ `executed_at, id` の順で選ぶ (#1635 の Codex P2)。**
    #
    # ⚠⚠ **`min(id)` / `max(id)` で選んではいけない。**行は run の**終了時**に insert
    # されるので、同じ source_id の run が重なると（reload で差し替えた直後・
    # IcalendarSource の追加ジョブ）**`id` の順と `executed_at`（開始時刻）の順が逆になる**。
    # 読む側（`recent_for` / `last_attempted` / `observed_since`）は `executed_at` 順なので、
    # `id` で守ると**最新でない行を守り、本当の根拠行を刈る**。
    def boundary_run_ids(func, dataset = self)
      order = func == :min ? [:executed_at, :id] : [Sequel.desc(:executed_at), Sequel.desc(:id)]
      rank = Sequel.function(:row_number).over(partition: :source_id, order:)
      return dataset.select(:id, rank.as(:edge_rank)).from_self.where(edge_rank: 1).select(:id)
    end

    # 「直近の配信試行」の根拠行もソースごとに 1 行だけ守る (#1504)。
    # ⚠ これを刈ると、取りこぼしを検知して赤くなったソースが retention_days の経過だけで
    # 黙って緑に戻る。**次に配信できたときだけ解除する**という仕様が壊れる。
    def last_attempted_ids
      return boundary_run_ids(:max, where(Sequel.lit('attempted_count > 0')))
    end

    # 「直近のエントリ処理段」の根拠行もソースごとに 1 行だけ守る (#1687)。
    # ⚠ これを刈ると、新着 1 件だけが落ちた run（配信の試行が 0 なので `last_attempted_ids` に
    # 掛からない）の取りこぼしが、確認しないまま保持期間の経過だけで緑に戻る。
    def last_entry_stage_ids
      return boundary_run_ids(:max, where(entry_stage: true))
    end
  end
end
