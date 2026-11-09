#!/usr/bin/env bash
# モロヘイヤ経由（WebhookShrieker → モロヘイヤ → Mastodon）のテスト用に、
# chubo2 の fedi-test-harness（Mastodon）の前段へモロヘイヤを立てる (#1452)。
#
#   test/harness/mulukhiya.sh up     # 取り出し → 設定 → 起動 → webhook の URL を .env.test へ（冪等）
#   test/harness/mulukhiya.sh down   # 止める（取り出したものと .env.test は残す）
#
#   ~/repos/chubo2/fedi-test-harness/mastodon/scripts/setup.sh   # 先に Mastodon を立てておく
#   test/harness/mulukhiya.sh up
#   set -a; source ~/repos/chubo2/fedi-test-harness/mastodon/.env.test; set +a
#   set -a; source ~/.cache/tomato-shrieker/mulukhiya-harness/.env.test; set +a
#   bundle exec rake test
#   test/harness/mulukhiya.sh down
#
# ⚠ モロヘイヤのリリースタグを**作業ツリーとは別の場所**へ取り出して動かす。開発機の
#   ~/repos/mulukhiya-toot-proxy（モロヘイヤ側の作業ツリー）には触れない。
# ⚠ モロヘイヤにはコンテナが無い。ハーネスのモロヘイヤ用 Redis（127.0.0.1:6379）を使う。
# ⚠ sidekiq と streaming は立てない（webhook の投稿は同期で済む）。/api/health は 503 になるが、
#   起動の確認は「応答が返ること」で見る。
set -euo pipefail

HARNESS_DIR="${FEDI_HARNESS_DIR:-$HOME/repos/chubo2/fedi-test-harness}"
ROOT="${MULUKHIYA_HARNESS_ROOT:-${XDG_CACHE_HOME:-$HOME/.cache}/tomato-shrieker/mulukhiya-harness}"
PORT="${MULUKHIYA_HARNESS_PORT:-3018}"
REPO='https://github.com/pooza/mulukhiya-toot-proxy.git'
APP="$ROOT/mulukhiya"
BASE="http://127.0.0.1:$PORT/mulukhiya"
PIDFILE="$APP/tmp/pids/puma.pid"

latest_tag() {
  git ls-remote --tags --refs "$REPO" 'v*' | awk -F/ '{print $3}' | sort -V | tail -1
}

running() {
  [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

checkout() {
  local version="${MULUKHIYA_VERSION:-$(latest_tag)}"
  mkdir -p "$ROOT"
  if [[ ! -d "$APP/.git" ]]; then
    git clone -q --depth 1 --branch "$version" "$REPO" "$APP"
  elif [[ "$(git -C "$APP" describe --tags 2>/dev/null)" != "$version" ]]; then
    git -C "$APP" fetch -q --depth 1 origin tag "$version"
    git -C "$APP" checkout -q "$version"
  fi
  echo "==> モロヘイヤ $version ($APP)"
  (cd "$APP" && bundle config set --local path vendor/bundle >/dev/null && bundle install --quiet)
}

# ハーネスの接続情報からモロヘイヤの local.yaml を組む。⚠ 毎回書き直す（ハーネスを作り直すとトークンが変わる）。
configure() {
  local env="$HARNESS_DIR/mastodon/.env.test"
  [[ -f "$env" ]] || {
    echo "==> ⚠ $env がありません。先に mastodon/scripts/setup.sh を実行してください。" >&2
    exit 1
  }
  (
    set -a
    # shellcheck disable=SC1090
    source "$env"
    set +a
    umask 077
    cd "$APP"
    PORT="$PORT" ruby -ryaml -rsecurerandom -e '
      File.write("config/local.yaml", {
        "controller" => "mastodon",
        "environment" => "development",
        "crypt" => {"password" => SecureRandom.hex(16)},
        "mastodon" => {"url" => ENV.fetch("MASTODON_URL")},
        "postgres" => {"dsn" => ENV.fetch("MASTODON_DB_DSN")},
        "agent" => {
          "info" => {"token" => ENV.fetch("MASTODON_INFO_ACCESS_TOKEN")},
          "test" => {"token" => ENV.fetch("MASTODON_ACCESS_TOKEN")},
        },
        "puma" => {"port" => Integer(ENV.fetch("PORT"))},
        "sidekiq" => {"auth" => {"password" => SecureRandom.hex(8)}},
      }.to_yaml)'
  )
}

start() {
  if running; then
    echo "==> モロヘイヤは起動済み (PID $(cat "$PIDFILE"))"
    return
  fi
  "$HARNESS_DIR/mulukhiya-redis/ctl.sh" up
  echo "==> モロヘイヤを起動 (127.0.0.1:$PORT)"
  mkdir -p "$APP/tmp/pids"
  # ⚠ `&` は puma だけに掛ける。`cd && puma &` と書くと、待つ側のサブシェルが呼び出し元の
  #   標準出力を握ったまま残り、`up | tail` のようなパイプが閉じない。
  (
    cd "$APP" || exit 1
    nohup bundle exec puma --config app/initializer/puma.rb >"$ROOT/puma.log" 2>&1 </dev/null &
  )
  for _ in $(seq 1 60); do
    if curl -s -o /dev/null "$BASE/api/health"; then
      return
    fi
    sleep 1
  done
  echo "==> ⚠ モロヘイヤが応答しません。$ROOT/puma.log を見てください。" >&2
  exit 1
}

# test アカウントに webhook のトークンを持たせ、URL を .env.test へ書き出す。
# ⚠ モロヘイヤが返す URL は Mastodon のホスト名（本番では nginx が /mulukhiya を振る）。
#   ハーネスには前段の nginx が無いので、モロヘイヤの待ち受けへ差し替える。
export_webhook() {
  local env="$HARNESS_DIR/mastodon/.env.test" token url
  token=$(grep '^MASTODON_ACCESS_TOKEN=' "$env" | cut -d= -f2-)
  curl -sf -o /dev/null -X POST -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' -d '{"command":"user_config"}' "$BASE/api/config/update"
  # shellcheck disable=SC2016 # Ruby の式なので展開しない
  url=$(curl -sf -H "Authorization: Bearer $token" "$BASE/api/config" |
    ruby -rjson -e 'print JSON.parse($stdin.read).dig("webhook", "url").to_s')
  [[ -n "$url" ]] || {
    echo '==> ⚠ webhook の URL を取れません（chubo2#232 の provisioning を確かめてください）。' >&2
    exit 1
  }
  url="$BASE/webhook/${url##*/mulukhiya/webhook/}"
  (
    umask 077
    cat >"$ROOT/.env.test" <<EOF
# test/harness/mulukhiya.sh が書き出したモロヘイヤの接続情報 (#1452)
MULUKHIYA_URL=$BASE
MULUKHIYA_WEBHOOK_URL=$url
EOF
  )
  echo "==> 接続情報を $ROOT/.env.test に書き出しました"
}

stop() {
  if running; then
    echo "==> モロヘイヤを停止 (PID $(cat "$PIDFILE"))"
    kill -TERM "$(cat "$PIDFILE")"
    for _ in $(seq 1 30); do
      running || break
      sleep 1
    done
  else
    echo '==> モロヘイヤは動いていません'
  fi
  "$HARNESS_DIR/mulukhiya-redis/ctl.sh" down
}

case "${1:-}" in
  up)
    # ⚠ 起動中は設定を書き換えない（crypt の鍵が変わると、動いているものと食い違う）。
    if ! running; then
      checkout
      configure
    fi
    start
    export_webhook
    ;;
  down)
    stop
    ;;
  *)
    echo "usage: $0 up|down" >&2
    exit 2
    ;;
esac
