#!/usr/bin/env bash
# 配信済みエントリを新旧の ginseng-fediverse に通して差分を出す。
# 使い方: sanitize_diff.sh v4.10.0   # 前リリースのタグ
set -eu
prev="$1"
script="$(dirname "$0")/sanitize_diff.rb"
rev=$(git show "$prev:Gemfile.lock" | awk '/ginseng-fediverse.git/{f=1} f&&/revision:/{print substr($2,1,12); exit}')
# ⚠ 旧版は bundler のチェックアウトを -I で読む（lock を戻して bundle install すると失敗する）
old=$(ls -d ~/.rbenv/versions/*/lib/ruby/gems/*/bundler/gems/ginseng-fediverse-"$rev" 2>/dev/null | head -1 || true)
if [ -z "$old" ]; then
  old="tmp/cache/ginseng-fediverse-$rev"
  [ -d "$old" ] || git clone -q https://github.com/pooza/ginseng-fediverse.git "$old"
  git -C "$old" checkout -q "$rev"
fi
echo "old: $old" >&2
export DSN="sqlite://$PWD/tmp/db/db.sqlite3"
# ⚠ >| を使う（zsh の noclobber 対策と同じ理由で、上書きを明示する）
bundle exec ruby "$script" >| tmp/cache/sanitize-new.txt
bundle exec ruby -I"$old/lib" "$script" >| tmp/cache/sanitize-old.txt
diff tmp/cache/sanitize-old.txt tmp/cache/sanitize-new.txt || true
