#!/usr/bin/env bash
# 本番（oscura）の本体とサテライト 3 本を pull し、bundle install して bundle check で確かめる。⚠ 再起動はしない。
# ⚠ リモート側でも set -e する。付けないと、途中のサテライトが失敗しても最後の 1 本が
# 成功すれば ssh が 0 を返し、不完全なまま再起動へ進んでしまう。
# ⚠ && でつながない（&& の途中の失敗は errexit の対象にならない）。
set -eu
# 本体
ssh oscura 'sudo -H -u deploy bash -lc "
  set -e
  cd ~/repos/tomato-shrieker
  git pull origin main
  bundle install
  bundle check"'

# サテライト 3 本（CommandSource の実行対象。それぞれ独立した Gemfile を持つ）
ssh oscura 'sudo -H -u deploy bash -lc "
  set -e
  RV=\$(cat ~/repos/tomato-shrieker/.ruby-version)
  for d in loquat:main shooby-do-bop:master dqdai-anniv:main; do
    cd ~/repos/\${d%%:*}
    git pull origin \${d##*:}
    RBENV_VERSION=\$RV bundle install
    RBENV_VERSION=\$RV bundle check
  done"'
