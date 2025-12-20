require 'sequel/model'

module TomatoShrieker
  class Entry < Sequel::Model(:entry)
    include Package

    alias to_h values

    def feed
      @feed ||= FeedSource.all.find {|v| v.id == values[:feed]}
      return @feed
    end

    def enclosures
      unless @enclosures
        uris = JSON.parse(enclosure_url)
        uris = [uris] unless uris.is_a?(Array)
        @enclosures = uris.map {|uri| Ginseng::URI.parse(uri)}.select(&:absolute?)
      end
      return @enclosures
    rescue
      return []
    end

    def tags
      unless @tags
        tags = Ginseng::Fediverse::TagContainer.new
        tags.concat(config['/feed/default_tags'])
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

    def create_template(type = :default, status = nil)
      template = feed.create_template(type)
      template[:entry] = self
      return template
    end

    def shriek
      feed.shriek(
        template: create_template,
        visibility: feed.visibility,
        attachments: enclosures.map {|v| {image_url: v.to_s}}.first(4),
      )
      logger.info(source: feed.id, entry: to_h, message: 'post')
    end

    alias post shriek

    def self.create(entry, feed = nil)
      parser = EntryParser.new(entry)
      parser.feed = feed if feed
      entry = Entry[Entry.insert(parser.parse)]
      return nil unless feed&.touched?
      return nil if entry.published < feed.time
      return entry
    rescue SQLite3::BusyException
      sleep(1)
      retry
    rescue Sequel::UniqueConstraintViolation
      return nil
    rescue => e
      logger.error(source: feed&.id, error: e, entry:)
      return nil
    end
  end
end
