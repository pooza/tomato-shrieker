# ディスク上の有効なソース定義の ID を `ID\t<id>` で出し、起動なら倒れる定義を `NG\t<id>` で出す。
# pending_sources.sh が標準入力から流す。
# 🔴 **`Source.all` を回さず、生の `/sources` を見る。**`Source.all` は判別キーが一致した定義しか
# 返さないので、unmatched な定義が一覧から黙って落ちる（`source reload` の拒否と同じ理由・#1589）。
# ⚠ DB には触らない（マイグレーションの前でも動く）。
entries = TomatoShrieker::Config.instance['/sources'].reject {|entry| entry['disable'] == true}
entries.each {|entry| puts "ID\t#{TomatoShrieker::Source.entry_id(entry)}"}
unstartable = entries.filter_map do |entry|
  errors = TomatoShrieker::SourceValidator.startup_errors(entry)
  [TomatoShrieker::Source.entry_id(entry), errors] unless errors.empty?
end
unstartable.each do |id, errors|
  puts "NG\t#{id}"
  errors.each {|v| puts "    - #{v}"}
end
