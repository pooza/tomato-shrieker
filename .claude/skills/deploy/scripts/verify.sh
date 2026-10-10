#!/usr/bin/env bash
# 再起動後の本番を読む（読むだけ）。版・再起動回数・/healthz・ソースの増減と内訳を出す。
set -eu
# ⚠ git describe は使わない（本番は pull でタグを取らないので古いタグからの距離が出る）
ssh oscura 'sudo -iu deploy bash -lc "cd ~/repos/tomato-shrieker && git log -1 --format=\"%h %s\" && grep -m1 \"^  version:\" config/application.yaml"'
ssh oscura 'systemctl show tomato-shrieker -p ActiveState -p ActiveEnterTimestamp -p NRestarts'
ssh oscura 'curl -s -o /dev/null -w "healthz %{http_code}\n" http://127.0.0.1:4567/healthz'
# 再起動の前（pending_sources.sh が控えた ID）からの増減。< は消えたソース、> は増えたソース
before="${TMPDIR:-/tmp}/tomato-shrieker-sources-before.txt"
status=$(ssh oscura 'curl -s http://127.0.0.1:4567/status.json')
if [ -e "$before" ]; then
  # ⚠ 控えは前回のデプロイのものが残りうる。時刻を出して、今回のものかを目で確かめられるようにする
  echo "控え: $(date -r "$before" '+%Y-%m-%d %H:%M:%S')"
  diff "$before" <(jq -r '.sources[].id' <<< "$status" | sort -u) && echo 'ソースの増減なし（再起動の前と同じ）' || true
else
  echo '⚠ 再起動の前の控えが無い（pending_sources.sh を先に実行していない）＝増減は比べられない'
fi
python3 -c '
import collections, json, sys
sources = json.load(sys.stdin)["sources"]
print(len(sources), dict(collections.Counter(str(v.get("last_status", "broken")) for v in sources)))
for v in sources:
    # ⚠ 組み立てに失敗したソースは {id, class, error} だけの行になる
    if "last_status" not in v:
        print(v["id"], "broken", v.get("error"))
    elif v["last_status"] not in ("success", None) or v["silent"] or v["undelivered"]:
        print(
            v["id"], v["last_status"], "streak", v["error_streak"], "/", v["error_streak_threshold"],
            "silent", v["silent"], "undelivered", v["undelivered"],
        )
' <<< "$status"
# いまの常駐（MainPID）が出したログから、この種の失敗を数える（どれも 0 が正常）。
# ⚠ リダイレクトの拒否は、そのソースが次に配信を試みたときに初めて出る。再起動の直後は 0 でも、
# 配信の少ないソースが一巡するまでもう一度見る。
# ⚠ `not started` だけは MainPID で絞らない（#1669 の Codex P2）。起動に失敗したプロセスは
# もう居らず、`Restart=always` で上がり直した常駐は別の番号なので、絞ると必ず 0 になる。
# 今日のログ全体から数える（ログは日次で回る）ので、再起動より前の分が混ざりうる。
ssh oscura '
  log=/var/log/tomato-shrieker.log
  pid=$(systemctl show tomato-shrieker -p MainPID --value)
  for word in "redirect refused" "process identity" "event dropped"; do
    printf "%s: %s\n" "$word" "$(grep -F "tomato-shrieker[$pid]:" "$log" | grep -cF "$word")"
  done
  printf "not started（今日のログ全体）: %s\n" "$(grep -cF "not started" "$log")"'
