#!/usr/bin/env bash
# google-news-rss-cleaner の open PR / issue・Dependabot アラートと、scylla での稼働状況を出す。
set -u
r=pooza/google-news-rss-cleaner
echo "=== $r ==="
gh pr list -R "$r" --state open
gh issue list -R "$r" --state open
gh api "repos/$r/dependabot/alerts" \
  --jq '[.[]|select(.state=="open")]|"Dependabot open \(length) \(map(.security_advisory.severity)|group_by(.)|map("\(.[0])=\(length)")|join(" "))"'
echo "=== gobou ==="
# 共有の Biome 設定。ginseng-style と同じくタグで固定するので、最新タグと比べる。
# ⚠ 作業ツリーではなく default ブランチ（origin/HEAD）の package.json を読む。
pkg=$(gh api "repos/$r/contents/package.json" --jq .content 2>/dev/null | base64 -d)
pin=$(jq -r '.devDependencies.gobou // empty' <<<"$pkg" | sed -n 's/.*#//p')
biome=$(jq -r '.devDependencies["@biomejs/biome"] // empty' <<<"$pkg")
latest=$(gh api repos/pooza/gobou/tags --jq '.[0].name' 2>/dev/null)
# gobou の版と Biome の版は揃える（gobou の README）。最新タグが要る Biome の版も出す。
want=$(gh api "repos/pooza/gobou/contents/package.json?ref=$latest" --jq .content 2>/dev/null |
  base64 -d | jq -r '.devDependencies["@biomejs/biome"]')
if [ -z "$pin" ]; then echo "gobou 未導入（最新 $latest）"
elif [ "$pin" = "$latest" ]; then echo "gobou $pin 最新・Biome $biome（gobou の版 $want）"
else echo "gobou $pin → $latest・Biome $biome → $want"
fi
echo "=== scylla ==="
# ⚠ ログはファイルに出ない（syslog → journal）。直近 24 時間のエラー・時間切れ・上流の制限を数える
ssh -o ConnectTimeout=5 scylla '
  systemctl show google-news-rss-cleaner -p ActiveState -p ActiveEnterTimestamp -p NRestarts
  journalctl -t google-news-rss-cleaner --since "-24h" -o cat --no-pager \
    | grep -oE "\"(event|via)\":\"(resolve-error|feed-parse-error|feed-rate-limited|feed-stale|timeout)\"" | sort | uniq -c
' || echo "scylla に届かない（外出中なら VPN）"
