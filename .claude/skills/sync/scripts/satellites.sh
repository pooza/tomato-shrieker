#!/usr/bin/env bash
# サテライト 3 本の open PR / issue と、default ブランチの最新の CI を出す。
set -u
for d in loquat shooby-do-bop dqdai-anniv; do
  b=$(gh repo view "pooza/$d" --json defaultBranchRef --jq .defaultBranchRef.name)
  echo "=== $d ($b) ==="
  gh pr list -R "pooza/$d" --state open
  gh issue list -R "pooza/$d" --state open
  # ⚠ -L 1 は最新を返すとは限らない（2026-10-01 に 9/3 の赤い run が返った）。件数で切ると取りこぼすので、
  # default ブランチの先頭コミットの run を直接引く
  sha=$(gh api "repos/pooza/$d/commits/$b" --jq .sha)
  gh run list -R "pooza/$d" -c "$sha" --json conclusion,createdAt \
    --jq "if length == 0 then \"CI (run なし) ${sha:0:7}\" else (sort_by(.createdAt)|last|\"CI \\(.conclusion) ${sha:0:7} \\(.createdAt)\") end"
done
