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
      searth_tags
      dest = values.slice(:feed, :title, :summary, :url, :enclosure_url, :published)
      dest[:feed] ||= feed.id
      dest[:enclosure_url] ||= enclosures.map(&:to_s).to_json
      dest[:title] = dest[:title].sanitize.gsub(/ [|-] .+$/, '') if dest[:title]
      dest[:summary] = dest[:summary].sanitize if dest[:summary]
      dest[:published] = dest[:published].getlocal
      dest[:extra_tags] ||= tags.to_a.to_json
      return dest
    end

    def enclosures
      enclosures = values[:enclosure_url]
      enclosures = [enclosures] unless enclosures.is_a?(Array)
      if values[:summary]
        uris = values[:summary].nokogiri
          .xpath('//img').map(&:to_h)
          .map {|values| values['src']}
          .map {|src| Ginseng::URI.parse(src)}
          .map(&:normalize)
        enclosures.concat(uris)
      end
      return enclosures.compact
    end

    private

    def searth_tags
      [:summary, :title].select {|k| values[k]}.each do |field|
        lines = values[field].tr('＃', '#').strip.each_line.to_a
        lines.reverse_each do |line|
          break unless line.match?(/^\s*(#[^\s]+\s?)+\s*$/)
          tags.merge(lines.pop.strip.split(/\s+/))
        end
        values[field] = lines.join("\n").strip
      end
    end
  end
end
