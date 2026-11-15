module TomatoShrieker
  class EntryParser
    attr_reader :values, :tags
    attr_accessor :feed

    include Package

    def initialize(entry)
      @values = entry.to_h unless entry.is_a?(Hash)
      @values ||= entry.clone
      @values.deep_symbolize_keys!
      @tags = Ginseng::Fediverse::TagContainer.new
    end

    def parse
      search_tags
      dest = values.slice(:feed, :title, :summary, :url, :enclosure_url, :published)
      dest[:feed] ||= feed.id
      dest[:enclosure_url] ||= enclosures.map(&:to_s).to_json
      dest[:title] = dest[:title].sanitize if dest[:title]
      dest[:summary] = dest[:summary].sanitize if dest[:summary]
      dest[:published] = dest[:published].getlocal
      dest[:extra_tags] ||= tags.to_a.to_json
      return dest
    end

    # フィードの enclosure（#1666）。⚠ 本文の `<img>` から添付を拾う `/enclosure/*` は 4.21.0 で
    # 廃止した（Nitter 前提の残骸・#1766）。
    def enclosures
      enclosures = values[:enclosure_url]
      enclosures = [enclosures] unless enclosures.is_a?(Array)
      return enclosures.compact
    end

    private

    def search_tags
      [:summary, :title].select {|k| values[k]}.each do |field|
        lines = values[field].tr('＃', '#').strip.each_line.to_a
        lines.clone.reverse_each do |line|
          break unless line.match?(/^[[:blank:]]*(#[^[:blank:]]+[[:blank:]]?)+[[:blank:]]*$/)
          tags.merge(lines.pop.strip.split(/[[:blank:]]+/))
        end
        values[field] = lines.join("\n").strip
      end
    end
  end
end
