#!/usr/bin/env bash
# google-news-rss-cleaner の open PR / issue・Dependabot アラートと、scylla での稼働状況を出す。
set -u
r=pooza/google-news-rss-cleaner
echo "=== $r ==="
gh pr list -R "$r" --state open
gh issue list -R "$r" --state open
gh api "repos/$r/dependabot/alerts" \
  --jq '[.[]|select(.state=="open")]|"Dependabot open \(length) \(map(.security_advisory.severity)|group_by(.)|map("\(.[0])=\(length)")|join(" "))"'
echo "=== scylla ==="
# ⚠ ログはファイルに出ない（syslog → journal）。直近 24 時間のエラーと時間切れを数える
ssh -o ConnectTimeout=5 scylla '
  systemctl show google-news-rss-cleaner -p ActiveState -p ActiveEnterTimestamp -p NRestarts
  journalctl -t google-news-rss-cleaner --since "-24h" -o cat --no-pager \
    | grep -oE "\"(event|via)\":\"(resolve-error|feed-parse-error|timeout)\"" | sort | uniq -c
' || echo "scylla に届かない（外出中なら VPN）"
