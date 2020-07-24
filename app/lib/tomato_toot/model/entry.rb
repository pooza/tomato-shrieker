require 'sequel/model'
require 'time'

module TomatoToot
  class Entry < Sequel::Model(:entry)
    alias to_h values

    def feed
      unless @feed
        Source.all do |source|
          next unless source.is_a?(FeedSource)
          next unless source.hash == values[:feed]
          @feed = source
          break
        end
      end
      return @feed
    end

    def body
      unless @body
        template = Template.new("toot.#{feed.template}")
        template[:feed] = feed
        template[:entry] = self
        @body = template.to_s
      end
      return @body
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

    def uri
      @uri ||= feed.create_uri(url)
      return @uri
    end

    def shriek
      v = {text: body, visibility: feed.visibility, attachments: []}
      v[:attachments].push(image_url: enclosure.to_s) if enclosure
      feed.shriek(v)
      feed.logger.info(entry: to_h, message: 'post')
    end

    alias post shriek

    def self.create(entry, feed = nil)
      values = entry.clone
      values = values.to_h unless values.is_a?(Hash)
      feed ||= Source.create(values['feed'])
      return if feed.touched? && entry['published'] <= feed.time
      id = insert(
        feed: feed.hash,
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
      feed.logger.error(error: e.message, entry: entry)
      return nil
    end

    def self.create_title(title, published, feed)
      return "#{published.getlocal.strftime('%Y/%m/%d %H:%M')} #{title}" unless feed.unique_title?
      return title
    rescue => e
      feed.logger.error(error: e.message, entry: entry)
      return title
    end
  end
end
