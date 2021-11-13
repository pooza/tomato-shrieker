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
      ['h1', 'h2', 'title', 'meta'].map do |v|
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

    def template
      template = feed.template.clone
      template[:feed] = feed
      template[:entry] = self
      return template
    end

    def shriek
      params = {template: template, visibility: feed.visibility, attachments: []}
      params[:attachments].push(image_url: enclosure.to_s) if enclosure
      feed.shriek(params)
      logger.info(source: feed.id, entry: to_h, message: 'post')
    end

    alias post shriek

    def self.create(entry, feed = nil)
      values = entry.clone
      values = values.to_h unless values.is_a?(Hash)
      feed ||= Source.create(values['feed'])
      return if feed.touched? && entry['published'] <= feed.time
      id = insert(
        feed: feed.id,
        title: create_title(values['title'], values['published'], feed),
        summary: values['summary']&.sanitize,
        url: values['url'],
        enclosure_url: values['enclosure_url'],
        published: values['published'].getlocal,
      )
      return Entry[id]
    rescue SQLite3::BusyException
      retry
    rescue Sequel::UniqueConstraintViolation
      return nil
    rescue => e
      logger.error(source: feed&.id, error: e, entry: entry)
      return nil
    end

    def self.create_title(title, published, feed)
      dest = title.sanitize if feed.unique_title?
      dest ||= "#{published.getlocal.strftime('%Y/%m/%d %H:%M')} #{title.sanitize}"
      return dest
    rescue => e
      logger.error(source: feed&.id, error: e, title: title)
      return title
    end
  end
end
