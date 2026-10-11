# 配信済みエントリの title / summary を sanitize_status に通して 1 行 1 件で出す
require 'ginseng/fediverse'
require 'sequel'
COLUMNS = [:title, :summary].freeze
db = Sequel.connect(ENV.fetch('DSN'))
db[:entry].order(:feed, :id).each do |row|
  COLUMNS.each do |col|
    src = row[col].to_s
    next if src.empty?
    out = begin
      Ginseng::Fediverse::Service.sanitize_status(src.dup)
    rescue => e
      "!!#{e.class}"
    end
    puts "#{row[:feed]}\t#{col}\t#{out.gsub(/\s+/, ' ')}"
  end
end
