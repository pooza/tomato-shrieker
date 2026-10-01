#!/usr/bin/env bash
# サテライト 3 本の open PR / issue と、default ブランチの最新の CI を出す。
set -u
for d in loquat shooby-do-bop dqdai-anniv; do
  b=$(gh repo view pooza/$d --json defaultBranchRef --jq .defaultBranchRef.name)
  echo "=== $d ($b) ==="
  gh pr list -R pooza/$d --state open
  gh issue list -R pooza/$d --state open
  # ⚠ -L 1 は最新を返すとは限らない（2026-10-01 に 9/3 の赤い run が返った）。作成日時で並べ直す
  gh run list -R pooza/$d -b $b -L 10 --json conclusion,headSha,createdAt \
    --jq 'sort_by(.createdAt)|last|"CI \(.conclusion) \(.headSha[0:7]) \(.createdAt)"'
done
