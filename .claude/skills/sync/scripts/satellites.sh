#!/usr/bin/env bash
# サテライト 3 本の open PR / issue と、default ブランチの最新の CI を出す。
set -u
for d in loquat shooby-do-bop dqdai-anniv; do
  b=$(gh repo view pooza/$d --json defaultBranchRef --jq .defaultBranchRef.name)
  echo "=== $d ($b) ==="
  gh pr list -R pooza/$d --state open
  gh issue list -R pooza/$d --state open
  gh run list -R pooza/$d -b $b -L 1 --json conclusion,headSha --jq '.[]|"CI \(.conclusion) \(.headSha[0:7])"'
done
