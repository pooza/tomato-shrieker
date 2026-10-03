#!/usr/bin/env bash
# 本番の有効ソースと Kuma のモニターを突き合わせ、active と maxretries / interval の内訳も出す。
# diff の < は Kuma に登録されていないソース、> は Kuma にあるが本番に無いソース。
set -u
kuma() {
  ssh mucor "sudo docker exec uptime-kuma sqlite3 -readonly /app/data/kuma.db \"$1\""
}
echo '=== diff（本番 / Kuma）'
diff <(ssh oscura 'curl -s http://127.0.0.1:4567/status.json' | jq -r '.sources[].id' | sort) \
     <(kuma "select name from monitor where name like 'tomato-shrieker %';" | sed 's/^tomato-shrieker //' | sort) &&
  echo '一致'
echo '=== active|件数'
kuma "select active, count(*) from monitor where name like 'tomato-shrieker %' group by active;"
echo '=== maxretries|件数'
kuma "select maxretries, count(*) from monitor where name like 'tomato-shrieker %' group by maxretries;"
echo '=== interval|件数'
kuma "select interval, count(*) from monitor where name like 'tomato-shrieker %' group by interval;"
