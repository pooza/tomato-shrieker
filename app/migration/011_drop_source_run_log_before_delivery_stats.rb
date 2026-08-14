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
# 🔴 境界を固定日付で書いてはいけない。010 が適用された時刻は DB ごとに違い、
# 4.4.0 から直接上げた環境では 010 と 011 が同時に走るので、既存行がすべて日付より新しくなる。
# そのとき計測前の行が観測開始時刻として凍りつき、silence_tolerance を設定したソースが
# 上げた直後に軒並み赤くなる。
#
# 代わりに attempted_count > 0 の最古行を「計測が始まっていた証拠」として使う。
# 010 は既存行を 0 で backfill するので、この条件に合う行は必ず 010 より後に書かれている。
# 証拠が無ければ計測済みの行が 1 行も無いということなので、全部捨てる。
# 証拠より古い no-op run も巻き添えで消えるが、観測開始が後ろへ動くだけで過検知にはならない。
#
# run_log は retention_days で捨てる前提の監視テレメトリなので、消して失うものはない。
# 新規 DB では 010 と 011 が同時に走るので削除対象はゼロ。不可逆なので down は持たない。
Sequel.migration do
  up do
    logs = self[:source_run_log]
    evidence = logs.where(Sequel.lit('attempted_count > 0')).order(:executed_at, :id).first
    logs = logs.where(Sequel.lit('executed_at < ?', evidence[:executed_at])) if evidence
    logs.delete
  end
end
