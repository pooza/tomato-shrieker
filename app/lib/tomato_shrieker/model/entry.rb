require 'sequel/model'

module TomatoShrieker
  class Entry < Sequel::Model(:entry)
    include Package

    alias to_h values

    def feed
      @feed ||= FeedSource.all.find {|v| v.id == values[:feed]}
      return @feed
    end

    def enclosure
      unless @enclosure
        return nil unless @enclosure ||= Ginseng::URI.parse(enclosure_url)
        return nil unless @enclosure.absolute?
      end
      return @enclosure
    rescue
      return nil
    end

    alias enclosure_uri enclosure

    def tags
      unless @tags
        tags = Ginseng::Fediverse::TagContainer.new
        tags.concat(feed.tags.clone)
        tags.concat(JSON.parse(extra_tags))
        tags.concat(fetch_remote_tags) if feed.remote_tagging?
        tags.select! {|v| feed.tag_min_length < v.to_s.length}
        @tags = tags.create_tags
      end
      return @tags
    rescue => e
      return [] unless feed
      logger.error(source: feed&.id, error: e)
      return feed.tags
    end

    def fetch_remote_tags
      contents = []
      ['h1', 'h2', 'h3', 'title', 'meta'].map do |v|
        contents.push(nokogiri.xpath("//#{v}").inner_text)
      end
      return feed.mulukhiya.search_hashtags(contents.join(' '))
    end

    def uri
      @uri ||= feed.create_uri(url)
      return @uri
    end

    def nokogiri
      @nokogiri ||= HTTP.new.get(uri).body.nokogiri
      return @nokogiri
    end

    def create_template(type = :default)
      template = feed.create_template(type)
      template[:entry] = self
      return template
    end

    def shriek
      params = {template: create_template, visibility: feed.visibility, attachments: []}
      params[:attachments].push(image_url: enclosure.to_s) if enclosure
      feed.shriek(params)
      logger.info(source: feed.id, entry: to_h, message: 'post')
    end

    alias post shriek

    def self.create(entry, feed = nil)
      values = create_values(entry.is_a?(Hash) ? entry.clone : entry.to_h)
      feed ||= Source.create(values[:feed])
      return if feed.touched? && values[:published] <= feed.time
      values[:feed] = feed.id
      return self[insert(values)]
    rescue SQLite3::BusyException
      sleep(1)
      retry
    rescue => e
      logger.error(source: feed&.id, error: e, entry:)
      return nil
    end

    def self.create_values(values) # rubocop:disable Metrics/AbcSize
      values.deep_symbolize_keys!
      values[:summary] = values[:summary].sanitize if values[:summary]
      values[:title] = values[:title].sanitize.gsub(/ [|-] .+$/, '') if values[:title]
      values[:published] = values[:published].getlocal
      values.except!(:entry_id, :author)
      tags = Set.new
      [:summary, :title].each do |field|
        lines = values[field].tr('＃', '#').strip.each_line.to_a
        lines.reverse_each do |line|
          break unless line.match?(/^\s*(#[^\s]+\s?)+\s*$/)
          tags.merge(lines.pop.strip.split(/\s+/))
        end
        values[field] = lines.join("\n").strip
      end
      values[:extra_tags] = tags.to_a.to_json
      return values
    end
  end
end
