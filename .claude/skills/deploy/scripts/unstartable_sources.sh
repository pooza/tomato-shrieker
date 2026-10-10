#!/usr/bin/env bash
# 起動で倒れるソース定義が残っていないことを確かめる（読むだけ）。残っていれば NG を出して非 0 で終わる。
# 🔴 **pull.sh の後・再起動の前に実行する。**再起動で走るのは pull した後のコードなので、
# 検査も同じコードで行う（古いコードの検査を通った定義が、新しい版の register で倒れうる）。
# ⚠ ID の突き合わせ（pending_sources.sh）では見えない: reload が拒否された後は古いジョブが
# 動き続けるので、稼働中の一覧は緑のまま＝再起動して初めて起動ループになる。
set -eu
ssh oscura 'sudo -H -u deploy bash -lc "cd ~/repos/tomato-shrieker && bundle exec ruby -Iapp/lib -rtomato_shrieker -"' \
  < "$(dirname "$0")/unstartable_sources.rb" || {
  echo '🔴 起動で倒れる定義がある（または検査に失敗した）＝このまま再起動しない' >&2
  exit 1
}
echo '起動で倒れる定義は無い'
