# 🔴 **「直近の試行」と「直近の段に入った run」を部分索引で引く (#1472)。**
#
# `/status.json` は 1 ソースにつき `last_attempted`（`attempted_count > 0`）と
# `last_entry_stage`（`entry_stage = 1`）を引く。どちらも条件の列が索引に無いので、
# `(source_id, executed_at)` を新しい順に舐めて当たるまで読む。⚠⚠ **一度も試行していない・
# 段に入っていないソースは毎回全行**（本番で 1 ソース 4,000 行前後）。
#
# 本番 DB のコピー（約 10 万行・63 ソース）で、2 本の合計が 135〜240ms → 25〜40ms。
# ⚠ `delivered_count > 0` は既存の `(source_id, delivered_count, executed_at)` で足りている
# （全ソースで 20ms 前後）ので足さない。
Sequel.migration do
  up do
    run [
      'CREATE INDEX IF NOT EXISTS source_run_log_attempted_index',
      'ON source_run_log (source_id, executed_at) WHERE attempted_count > 0',
    ].join(' ')
    run [
      'CREATE INDEX IF NOT EXISTS source_run_log_entry_stage_index',
      'ON source_run_log (source_id, executed_at) WHERE entry_stage = 1',
    ].join(' ')
  end

  down do
    run 'DROP INDEX IF EXISTS source_run_log_attempted_index'
    run 'DROP INDEX IF EXISTS source_run_log_entry_stage_index'
  end
end
