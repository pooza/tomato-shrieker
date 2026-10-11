#!/usr/bin/env bash
# 再起動の前に、稼働中のソースとディスク上の有効な定義を突き合わせる（読むだけ）。
# 🔴 再起動は、ディスクに置かれたまま reload されていない定義を全部読み込む（#1649）。
#   - diff の > は「再起動で増えるソース」、< は「再起動で消えるソース」（0 で終わる。意図を確かめる）
#   - NG は「起動で倒れる定義」（非 0 で終わる。再起動しない）。⚠ 見るのはスケジュールと判別キーだけ
# 稼働中の ID は手元に控え、再起動後に verify.sh が増減を出す。
#
# 🔴 **pull.sh の後・再起動の前に実行する。**再起動で走るのは pull した後のコードなので、定義も
# 同じコードで読む（新しい版で増えたソース種別の定義や、新しい版の検査で倒れる定義は、古い
# コードからは見えない）。⚠ DB を読む CLI（`source status` など）は使わない — pull の後・
# 再起動の前はスキーマが古く、マイグレーションが要る版では落ちる。
#
# ⚠ pipefail を付け、両方の一覧を受け取ってから比べる。付けないと ssh / curl / jq が
# 失敗しても末尾の sort が 0 を返し、空どうしを比べて「一致」と答える。
set -euo pipefail
before="${TMPDIR:-/tmp}/tomato-shrieker-sources-before.txt"
running=$(ssh oscura 'curl -sf http://127.0.0.1:4567/status.json' | jq -er '.sources[].id' | sort -u)
out=$(ssh oscura 'sudo -H -u deploy bash -lc "cd ~/repos/tomato-shrieker && bundle exec ruby -Iapp/lib -rtomato_shrieker -"' \
  < "$(dirname "$0")/enabled_sources.rb")
disk=$(awk -F'\t' '$1=="ID"{print $2}' <<< "$out" | sort -u)
if [ -z "$running" ] || [ -z "$disk" ]; then
  echo '一覧が空（取得に失敗している）＝突き合わせていない' >&2
  exit 1
fi
ng=$(awk '/^NG\t/{f=1} f' <<< "$out")
if [ -n "$ng" ]; then
  printf '%s\n' "$ng"
  echo '🔴 起動で倒れる定義がある＝このまま再起動しない（直すか disable する）' >&2
  exit 1
fi
# ⚠ 「起動できる」とは言わない（#1674 の Codex P1）。見ているのは `source reload` の拒否と同じ
# 検査（スケジュールと判別キー）だけで、登録の途中で起きる失敗（`command:` のソースの
# `bundle install`・`/source/dir` の誤り）は見ていない。そこは pull.sh の `bundle check` と、
# 再起動の後の verify.sh（`not started` の件数・NRestarts）で受ける。
echo 'スケジュール・判別キーで倒れる定義は無い（登録時の失敗は見ていない）'
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
