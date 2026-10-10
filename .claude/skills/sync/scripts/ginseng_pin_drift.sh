#!/usr/bin/env bash
# ginseng-* のピンが上流からどれだけ遅れているかを、本体とサテライト 3 本について出す。
# ⚠ 作業ツリーの Gemfile.lock ではなく追跡ブランチから読む。tomato 自身だけ origin/develop (#1550)。
set -u
for d in tomato-shrieker loquat shooby-do-bop dqdai-anniv; do
  ref=origin/HEAD; [ "$d" = tomato-shrieker ] && ref=origin/develop
  git -C ~/repos/"$d" fetch -q origin
  git -C ~/repos/"$d" show "$ref:Gemfile.lock" |
  awk '
    /github\.com\/pooza\/ginseng-/{g=$2; sub(/.*\//,"",g); sub(/\.git/,"",g); r=""; t="-"; f=1}
    f&&/revision:/{r=$2} f&&/ tag:/{t=$2} f&&/specs:/{print g, r, t; f=0}' |
  while read -r gem rev tag; do
    if [ "$tag" != - ]; then
      # タグ固定の gem は main と比べない（main には未タグのコミットが常に積まれている）。
      # gh api は HTTP エラーでも本文を標準出力へ出すので、終了コードで見る。
      latest=$(gh api "repos/pooza/$gem/tags" --jq '.[0].name' 2>/dev/null) || latest=""
      if [ -z "$latest" ]; then lag=""
      elif [ "$tag" = "$latest" ]; then lag=0
      else lag="$tag → $latest"; fi
    else
      lag=$(gh api "repos/pooza/$gem/compare/$rev...main" --jq .ahead_by 2>/dev/null) || lag=""
    fi
    printf '%-16s %-18s %s\n' "$d" "$gem" "${lag:-?}"
  done
done
