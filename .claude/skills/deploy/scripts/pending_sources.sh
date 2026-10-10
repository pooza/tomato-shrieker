#!/usr/bin/env bash
# 再起動の前に、稼働中のソースとディスク上の有効な定義を突き合わせる（読むだけ）。
# 🔴 再起動は、ディスクに置かれたまま reload されていない定義を全部読み込む（#1649）。
# diff の > は「再起動で増えるソース」、< は「再起動で消えるソース」。
# 稼働中の ID は手元に控え、再起動後に verify.sh が増減を出す。
#
# 🔴 **pull.sh より前に実行する。**`source status` は DB を読むので、pull した後（新しいコード・
# 古いスキーマ）に叩くと、マイグレーションが要る版では落ちる。ソース定義は git 管理外なので、
# pull の前後で突き合わせの答えは変わらない。
#
# ⚠ pipefail を付け、両方の一覧を受け取ってから比べる。付けないと ssh / curl / jq が
# 失敗しても末尾の sort が 0 を返し、空どうしを比べて「一致」と答える。
set -euo pipefail
before="${TMPDIR:-/tmp}/tomato-shrieker-sources-before.txt"
running=$(ssh oscura 'curl -sf http://127.0.0.1:4567/status.json' | jq -er '.sources[].id' | sort)
# ⚠ `source list` は無効ソースも出すので使わない。`source status` は有効な定義だけを出す
disk=$(ssh oscura 'sudo -H -u deploy bash -lc "cd ~/repos/tomato-shrieker && bin/shrieker source status --json"' |
  jq -er '.[].id' | sort)
if [ -z "$running" ] || [ -z "$disk" ]; then
  echo '一覧が空（取得に失敗している）＝突き合わせていない' >&2
  exit 1
fi
printf '%s\n' "$running" >| "$before"
echo "稼働中 $(wc -l < "$before") 件"
# ⚠ 差分があっても 0 で終わる（増減は運用者が確かめるもので、失敗ではない）。diff 自体の失敗（2 以上）だけ伝える
rc=0
diff "$before" <(printf '%s\n' "$disk") || rc=$?
case $rc in
  0) echo '一致（再起動で増減するソースは無い）' ;;
  1) echo '⚠ 再起動でソースが増減する。意図したものかを確かめる' ;;
  *) exit "$rc" ;;
esac
