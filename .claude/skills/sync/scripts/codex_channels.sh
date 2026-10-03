#!/usr/bin/env bash
# Codex の結果を 4 経路（review・インライン・issue コメント・PR へのリアクション）すべてから読む (#1618)。
# インラインの指摘は「返信」と「👍 / 👎」の有無を出し、どちらかが欠けているもの（＝未処理）は本文も出す。
# 使い方: codex_channels.sh <PR番号>...   引数なしなら直近にマージされた 5 本
set -eu
r=repos/pooza/tomato-shrieker
bot='select(.user.login=="chatgpt-codex-connector[bot]")'
prs=("$@")
[ ${#prs[@]} -eq 0 ] && mapfile -t prs < <(gh pr list --state merged --limit 5 --json number --jq '.[].number')
for n in "${prs[@]}"; do
  echo "=== #$n"
  gh api --paginate "$r/pulls/$n/reviews" --jq ".[]|$bot|\"review \(.submitted_at) \(.commit_id[0:7])\""
  # ⚠ 全ページを 1 本の配列にまとめてから読む。返信の有無は全件を突き合わせるので、
  # ページごとに --jq を回すと、ページをまたいだ返信を「無」と読む
  gh api --paginate "$r/pulls/$n/comments?per_page=100" | jq -rs "
    add as \$all
    | \$all[] | $bot
    | .id as \$id
    | (any(\$all[]; .in_reply_to_id == \$id)) as \$replied
    | ((.reactions[\"+1\"] + .reactions[\"-1\"]) > 0) as \$reacted
    | \"inline \(.id) \(.path):\(.line // .original_line) 返信=\(if \$replied then \"済\" else \"無\" end) リアクション=\(if \$reacted then \"済\" else \"無\" end)\",
      (if \$replied and \$reacted then empty else \"  🔴 未処理\n\" + (.body | gsub(\"(?m)^\"; \"  | \")) end)"
  gh api --paginate "$r/issues/$n/comments" --jq ".[]|$bot|\"comment \(.created_at) \(.body | split(\"\n\")[0])\""
  gh api --paginate "$r/issues/$n/reactions" --jq ".[]|$bot|\"reaction \(.content) \(.created_at)\""
done
