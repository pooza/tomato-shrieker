#!/usr/bin/env bash
# 旧版から新版までに跨いだリリースノートを全部出す（旧版は含まず、新版は含む）。
# 使い方: release_notes.sh <gem> <旧版> <新版>   例: release_notes.sh ginseng-fediverse 2.0.0 3.1.0
# ⚠ リリースは作成順に並び、旧系列の修正版が間に挟まるので、版の範囲で絞る。
set -eu
gem=$1 old=$2 new=$3
for t in $(gh api --paginate repos/pooza/$gem/releases --jq '.[].tag_name' | sed 's/^v//' | sort -V); do
  [ "$t" != "$old" ] && [ "$(printf '%s\n' "$old" "$t" | sort -V | tail -1)" = "$t" ] &&
  [ "$(printf '%s\n' "$t" "$new" | sort -V | tail -1)" = "$new" ] &&
  gh api repos/pooza/$gem/releases/tags/v$t --jq '"## \(.tag_name)\n\(.body)"'
done
exit 0
