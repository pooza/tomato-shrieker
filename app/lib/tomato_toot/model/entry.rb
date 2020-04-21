require 'sequel/model'
require 'time'

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

    alias time published

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

    def new?
      return false unless feed
      return false unless published
      return true unless feed.touched?
      return feed.time < published
    rescue => e
      feed.logger.error(error: e.message, entry: values)
      return false
    end

    def tooted?
      return tooted.present?
    end

    def touch
      update(tooted: Time.now.to_s) unless tooted?
    rescue SQLite3::ConstraintException
      return nil
    rescue => e
      feed.logger.error(error: e.message, entry: values)
    end

    def post
      return false if tooted?
      return if feed.recent? && !new?
      if feed.mastodon
        unless toot.code == 200
          raise Ginseng::GatewayError, "response #{toot.code} #{feed.mastodon.uri}"
        end
      end
      feed.hooks do |hook|
        message = {text: body}
        message[:attachments] = [{image_url: enclosure.to_s}] if enclosure
        response = hook.say(message, :hash)
        unless response.code == 200
          raise Ginseng::GatewayError, "response #{response.code} #{hook.uri}"
        end
      end
      touch
      return true
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

    def self.get(feed, entry)
      h = entry.to_h
      values = {
        feed: feed.hash,
        title: h['title'],
        summary: h['summary'],
        url: h['url'],
        enclosure_url: h['enclosure_url'],
      }
      entry = Entry.first(values)
      return entry if entry.is_a?(Entry)
      values[:published] = h['published'] || Time.now
      entry = Entry.create(values)
      return entry if entry.is_a?(Entry)
    rescue SQLite3::ConstraintException, Sequel::NotNullConstraintViolation
      return nil
    rescue => e
      feed.logger.error(error: e.message, entry: values)
    end
  end
end
