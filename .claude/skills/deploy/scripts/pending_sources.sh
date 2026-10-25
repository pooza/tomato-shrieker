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
# ⚠ 控えはリポジトリの tmp/ に置く (#1672)。共有の /tmp に決まった名前で置くと、`>|` が
# 他人の置いたシンボリックリンクを辿る。
before="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/tmp/cache/deploy-sources-before.txt"
status=$(ssh oscura 'curl -sf http://127.0.0.1:4567/status.json')
running=$(jq -er '.sources[].id' <<< "$status" | sort -u)
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
# 🔴 #1477: コマンドの依存が欠けているソース。起動は通るが、走るたびに落ちる。
bundle_ng=$(awk -F'\t' '$1=="BUNDLE"{print "BUNDLE\t" $2 "\t" $3}' <<< "$out")
if [ -n "$bundle_ng" ]; then
  printf '%s\n' "$bundle_ng"
  echo '🔴 コマンドの依存が欠けている＝そのディレクトリで bundle install してから再起動する' >&2
  exit 1
fi
# ⚠ 「起動できる」とは言わない（#1674 の Codex P1）。見ているのは `source reload` の拒否と同じ
# 検査（スケジュールと判別キー）とコマンドの依存（#1477）だけで、登録の途中で起きるほかの失敗
# （`command:` のソースが `bundle …` で始まるときの `bundle install` の失敗など）は見ていない。
# そこは再起動の後の verify.sh（`not started` の件数・NRestarts）で受ける。
echo 'スケジュール・判別キー・コマンドの依存で倒れる定義は無い（登録時のほかの失敗は見ていない）'
mkdir -p "$(dirname "$before")"
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
# 🔴 #1672: 編集したまま reload していない定義。再起動で黙って有効になる（宛先やスケジュールの変更）。
# 稼働中の digest（scheduler が登録した定義）とディスク上の定義の digest を、両方にある id で比べる。
# ⚠ 稼働中の digest が null のソース（登録に失敗している）は比べない。⚠ 4.17 以前の版は digest を
# 出さないので、そのときは「変更なし」と言わずに比べていないと出す。⚠ join は sort と同じ照合順が要る。
running_digests=$(jq -r '.sources[] | select(.digest != null) | "\(.id)\t\(.digest)"' <<< "$status" | LC_ALL=C sort)
# ⚠ ディスク側の DIGEST 行が 0 件でも「変更なし」と言わない（空どうしの join は空＝一致に見える）。
disk_digests=$(awk -F'\t' '$1=="DIGEST"{print $2 "\t" $3}' <<< "$out" | LC_ALL=C sort)
changed=$(LC_ALL=C join -t $'\t' <(printf '%s\n' "$running_digests") <(printf '%s\n' "$disk_digests") \
  | awk -F'\t' '$2 != $3 {print $1}')
if [ -z "$running_digests" ]; then
  echo '⚠ 稼働中の版が digest を出していない＝定義の変更は比べていない'
elif [ -z "$disk_digests" ]; then
  echo '⚠ ディスク上の定義の digest が取れていない＝定義の変更は比べていない'
elif [ -n "$changed" ]; then
  printf '~ %s\n' $changed
  echo '⚠ 再起動で定義が変わるソースがある（reload していない編集）。意図したものかを確かめる'
else
  echo '定義の変更なし（reload していない編集は無い）'
fi
