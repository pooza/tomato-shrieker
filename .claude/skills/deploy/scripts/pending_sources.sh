#!/usr/bin/env bash
# 再起動の前に、稼働中のソースとディスク上の有効な定義を突き合わせる（読むだけ）。
# 🔴 再起動は、ディスクに置かれたまま reload されていない定義を全部読み込む（#1649）。
# diff の > は「再起動で増えるソース」、< は「再起動で消えるソース」。
# 稼働中の ID は手元に控え、再起動後に verify.sh が増減を出す。
set -eu
before="${TMPDIR:-/tmp}/tomato-shrieker-sources-before.txt"
ssh oscura 'curl -s http://127.0.0.1:4567/status.json' | jq -r '.sources[].id' | sort >| "$before"
echo "稼働中 $(wc -l < "$before") 件"
# ⚠ `source list` は無効ソースも出すので使わない。`source status` は有効な定義だけを出す
diff "$before" \
  <(ssh oscura 'sudo -H -u deploy bash -lc "cd ~/repos/tomato-shrieker && bin/shrieker source status --json"' |
    jq -r '.[].id' | sort) &&
  echo '一致（再起動で増減するソースは無い）'
