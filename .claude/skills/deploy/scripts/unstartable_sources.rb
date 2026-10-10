# 起動なら倒れるソース定義を出す。`source reload` の拒否と同じ検査で、HUP は送らない。
# ⚠ DB には触らない（マイグレーションの前でも動く）。unstartable_sources.sh が標準入力から流す。
unstartable = TomatoShrieker::Config.instance['/sources'].filter_map do |entry|
  errors = TomatoShrieker::SourceValidator.startup_errors(entry)
  [TomatoShrieker::Source.entry_id(entry), errors] unless errors.empty?
end
unstartable.each do |id, errors|
  puts "NG\t#{id}"
  errors.each {|v| puts "    - #{v}"}
end
exit(unstartable.empty? ? 0 : 1)
