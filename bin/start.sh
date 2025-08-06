#!/bin/sh

# rcスクリプトから export される前提
: "${tomato_shrieker_user:=$(whoami)}"
: "${tomato_shrieker_path:="/usr/home/${tomato_shrieker_user}/repos/tomato-shrieker"}"

export HOME=$(eval echo "~${tomato_shrieker_user}")
export PATH="${HOME}/.rbenv/bin:/usr/local/bin:${PATH}"
export LANG=ja_JP.UTF-8
export LC_ALL=ja_JP.UTF-8

eval "$(rbenv init -)"
cd "$tomato_shrieker_path" || exit 1
exec bundle exec rake start
