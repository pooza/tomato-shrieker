# 配信計測 (010) より前に書かれた run_log 行を一度だけ捨てる (#1483)。
#
# attempted_count / delivered_count は 010 で null: false, default: 0 として足したため、
# 計測が始まる前の行と「本当に何も配信しなかった run」を列から区別できない。
# SourceRunLog.observed_since は「観測を始めてからずっと配信していない」ことを
# 沈黙の根拠に使うので、計測していなかった期間の行が混じると期間を過大に見積もる。
#
# 通常の prune でも retention_days 経過後に消えるが、同じ #1483 で入れた
# first_run_ids の保護がソースごとに最古行を 1 行だけ永久に残すため、
# 掃除しないと計測前の行が観測開始時刻として凍りつく。
#
# run_log は retention_days で捨てる前提の監視テレメトリなので、消して失うものはない。
# 新規 DB では 010 と 011 が同時に走るので削除対象はゼロ。不可逆なので down は持たない。
Sequel.migration do
  up do
    # 本番 (oscura) で 010 が適用され、delivered_count の記録が始まった日。
    cutoff = Time.new(2026, 8, 3)
    self[:source_run_log].where(Sequel.lit('executed_at < ?', cutoff)).delete
  end
end
