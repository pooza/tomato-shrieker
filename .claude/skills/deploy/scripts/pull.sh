#!/usr/bin/env bash
# 本番（oscura）の本体とサテライト 3 本を pull し、bundle install する。⚠ 再起動はしない。
set -eu
# 本体
ssh oscura 'sudo -H -u deploy bash -lc "cd ~/repos/tomato-shrieker && git pull origin main && bundle install"'

# サテライト 3 本（CommandSource の実行対象。それぞれ独立した Gemfile を持つ）
ssh oscura 'sudo -H -u deploy bash -lc "
  RV=\$(cat ~/repos/tomato-shrieker/.ruby-version)
  for d in loquat:main shooby-do-bop:master dqdai-anniv:main; do
    cd ~/repos/\${d%%:*} && git pull origin \${d##*:} && RBENV_VERSION=\$RV bundle install
  done"'
