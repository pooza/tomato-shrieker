require 'sequel/model'
require 'time'
require 'sanitize'

module TomatoToot
  class Entry < Sequel::Model(:entry)
    alias to_h values

    def feed
      unless @feed
        Feed.all do |feed|
          next unless feed.hash == values[:feed]
          @feed = feed
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

    def post
      toot if feed.mastodon?
      feed.hooks do |hook|
        message = {text: body}
        message[:attachments] = [{image_url: enclosure.to_s}] if enclosure
        hook.say(message, :hash)
      end
      feed.logger.info(entry: to_h, message: 'post')
      return true
    rescue => e
      feed.logger.error(e)
    end

    def toot
      ids = []
      ids.push(feed.mastodon.upload_remote_resource(enclosure)) if enclosure
      return feed.mastodon.toot(
        status: body,
        visibility: feed.visibility,
        media_ids: ids,
      )
    end

    def self.create_new(feed, entry)
      return if feed.touched? && entry.published <= feed.time
      values = entry.to_h
      id = insert(
        feed: feed.hash,
        title: sanitize(values['title']),
        summary: sanitize(values['summary']),
        url: values['url'],
        enclosure_url: values['enclosure_url'],
        published: values['published'].getlocal,
      )
      created = Entry[id]
      feed.logger.info(entry: created.to_h, message: 'created')
      return created
    rescue SQLite3::BusyException
      retry
    rescue Sequel::UniqueConstraintViolation
      return nil
    rescue => e
      feed.logger.error(error: e.message, entry: entry)
      return nil
    end

    def self.clean
      dataset.destroy
    end

    def self.sanitize(text)
      text = Sanitize.clean(text)
      text = Nokogiri::HTML.parse(text).text
      return text
    end
  end
end
