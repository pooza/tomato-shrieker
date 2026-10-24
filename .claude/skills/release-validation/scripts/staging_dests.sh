#!/usr/bin/env bash
# 検証用ソースの宛先（ステージングのトークンと webhook URL）を、ステージングから取ってきて埋める (#1481)。
# install_sources.sh の後に流す。埋め済み（プレースホルダが無い）ファイルは触らない。
#
# 🔴 **値は画面に出さない・コマンド行に載せない。**ssh の出力をそのまま標準入力で置き換えに渡す。
# 正本はステージング側（dev25 の ~mastodon/bot-webhook/tomato_test_bot/・dev27 の ~misskey/misskey_accounts.txt）。
# アカウントの作り方は chubo2 の tools/bot-webhook/（Mastodon）と、このスキルの SKILL.md（Misskey）。
set -euo pipefail
dir=config/sources

# <ファイル> <プレースホルダ>。値は標準入力から読む。
fill() {
  python3 -c '
import sys
path, key = sys.argv[1:3]
value = sys.stdin.read().strip()
if not value:
    sys.exit(f"empty value for {key}")
body = open(path).read()
open(path, "w").write(body.replace(key, value))
' "$1" "$2"
  echo "filled $1 ($2)"
}

needs() {
  [ -e "$dir/$1" ] && grep -q "$2" "$dir/$1"
}

if needs test-mastodon.yaml __MASTODON_TOKEN__; then
  ssh dev25 'sudo -iu mastodon sh -c "cd ~/repos/mastodon && RAILS_ENV=production bin/rails runner -"' <<'RUBY' \
    | tail -1 | fill "$dir/test-mastodon.yaml" __MASTODON_TOKEN__
print Doorkeeper::AccessToken.find(File.read('/home/mastodon/bot-webhook/tomato_test_bot/token.id').to_i).token
RUBY
fi
if needs test-webhook.yaml __WEBHOOK_URL__; then
  ssh dev25 'sudo -iu mastodon cat ~mastodon/bot-webhook/tomato_test_bot/url' \
    | fill "$dir/test-webhook.yaml" __WEBHOOK_URL__
fi
if needs test-misskey.yaml __MISSKEY_TOKEN__; then
  ssh dev27 'sudo -n -u misskey awk '\''$1=="tomato_test"{for(i=2;i<=NF;i++) if($i ~ /^token=/){sub("token=","",$i); print $i}}'\'' ~misskey/misskey_accounts.txt' \
    | fill "$dir/test-misskey.yaml" __MISSKEY_TOKEN__
fi
