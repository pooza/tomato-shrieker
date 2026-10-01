#!/usr/bin/env bash
# Codex の結果を 4 経路（review・インライン・issue コメント・PR へのリアクション）すべてから読む (#1618)。
# 使い方: codex_channels.sh <PR番号>...   引数なしなら直近にマージされた 5 本
set -eu
r=repos/pooza/tomato-shrieker
bot='select(.user.login=="chatgpt-codex-connector[bot]")'
prs=("$@")
[ ${#prs[@]} -eq 0 ] && mapfile -t prs < <(gh pr list --state merged --limit 5 --json number --jq '.[].number')
for n in "${prs[@]}"; do
  echo "=== #$n"
  gh api $r/pulls/$n/reviews --jq ".[]|$bot|\"review \(.submitted_at) \(.commit_id[0:7])\""
  gh api $r/pulls/$n/comments --jq ".[]|$bot|\"inline \(.id) \(.path):\(.line // .original_line)\""
  gh api $r/issues/$n/comments --jq ".[]|$bot|\"comment \(.created_at)\""
  gh api $r/issues/$n/reactions --jq ".[]|$bot|\"reaction \(.content) \(.created_at)\""
done
