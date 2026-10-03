#!/usr/bin/env bash
# fetch できるテスト用ソースを順に dry-run する（Shrieker は呼ばない）。
# ⚠ 失敗しても最後まで回し、1 件でも失敗していたら非 0 で終わる。
set -u
failed=''
for id in test-ical-schedule test-ical-remind test-youtube-channel test-youtube-keyword test-github \
  test-google-news-cleaner test-google-news-piefed; do
  echo "===== $id ====="
  if out=$(bundle exec bin/shrieker source fetch "$id" 2>&1); then
    echo "$out" | head -20
  else
    echo "$out" | head -20
    failed="$failed $id"
  fi
done
if [ -n "$failed" ]; then
  echo "FAILED:$failed" >&2
  exit 1
fi
