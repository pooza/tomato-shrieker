require 'sequel/model'
require 'nokogiri'
require 'time'

module TomatoShrieker
  class Entry < Sequel::Model(:entry)
    alias to_h values

    def feed
      unless @feed
        Source.all do |source|
          next unless source.is_a?(FeedSource)
          next unless source.id == values[:feed]
          @feed = source
          break
        end
      end
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
        tags.concat(fetch_remote_tags) if feed.tagging?
        tags.select! {|v| feed.tag_min_length < v.to_s.length}
        @tags = tags.create_tags
      end
      return @tags
    rescue => e
      return [] unless feed
      feed.logger.error(error: e)
      return feed.tags
    end

    def fetch_remote_tags
      html = Nokogiri::HTML.parse(HTTP.new.get(uri).body, nil, 'utf-8')
      contents = []
      ['h1', 'h2', 'title', 'meta'].map do |v|
        contents.push(html.xpath("//#{v}").inner_text)
      end
      return feed.mulukhiya.search_hashtags(contents.join(' '))
    end

    def uri
      @uri ||= feed.create_uri(url)
      return @uri
    end

    def create_body(params = {})
      template = Template.new(feed.template)
      template.params = params
      template[:feed] = feed
      template[:entry] = self
      @body = template.to_s
    end

    def shriek
      v = {
        text: create_body(tag: true),
        text_without_tags: create_body,
        visibility: feed.visibility,
        attachments: [],
      }
      v[:attachments].push(image_url: enclosure.to_s) if enclosure
      feed.shriek(v)
      feed.logger.info(source: feed.id, entry: to_h, message: 'post')
    end

    alias post shriek

    def self.create(entry, feed = nil)
      values = entry.clone
      values = values.to_h unless values.is_a?(Hash)
      feed ||= Source.create(values['feed'])
      return if feed.touched? && entry['published'] <= feed.time
      id = insert(
        feed: feed.id,
        title: create_title(values['title'], values['published'], feed).sanitize,
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
      feed.logger.error(error: e, entry: entry)
      return nil
    end

    def self.create_title(title, published, feed)
      return "#{published.getlocal.strftime('%Y/%m/%d %H:%M')} #{title}" unless feed.unique_title?
      return title
    rescue => e
      feed.logger.error(error: e, entry: entry)
      return title
    end
  end
end
