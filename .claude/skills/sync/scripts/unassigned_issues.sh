#!/usr/bin/env bash
# 未割当の open issue（0 件であること）と、保留中の issue を出す。
set -eu
echo '=== 未割当'
gh issue list --state open --limit 200 --json number,title,milestone \
  --jq '.[] | select(.milestone == null) | "#\(.number) \(.title)"'
echo '=== on-hold'
gh issue list --state open --label on-hold --json number,title,milestone \
  --jq '.[] | "#\(.number) [\(.milestone.title)] \(.title)"'
