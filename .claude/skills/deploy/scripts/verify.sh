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
  diff "$before" <(jq -r '.sources[].id' <<< "$status" | sort) && echo 'ソースの増減なし（再起動の前と同じ）' || true
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
