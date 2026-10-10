#!/usr/bin/env bash
# テスト用ソースのテンプレートを config/sources/ へ置く。
# ⚠ 既にあるファイルは上書きしない（test-google-news-piefed.yaml には実パスワードが入っている）。
set -eu
src="$(dirname "$0")/../sources"
for f in "$src"/test-*.yaml; do
  dest="config/sources/$(basename "$f")"
  if [ -e "$dest" ]; then
    echo "skip   $dest"
  else
    cp "$f" "$dest"
    # ⚠ test-google-news-piefed.yaml には後で平文のパスワードを書き込む
    chmod 600 "$dest"
    echo "create $dest"
  fi
done
