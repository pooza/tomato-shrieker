#!/usr/bin/env bash
# fetch できるテスト用ソースを順に dry-run する（Shrieker は呼ばない）。
set -eu
for id in test-ical-schedule test-ical-remind test-youtube-channel test-youtube-keyword test-github \
  test-google-news-cleaner test-google-news-piefed; do
  echo "===== $id ====="
  bundle exec bin/shrieker source fetch "$id" 2>&1 | head -20
done
