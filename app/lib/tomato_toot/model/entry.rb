require 'sequel/model'
require 'time'

Sequel.connect(TomatoToot::Environment.dsn)

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
      return true unless feed.touched?
      return feed.time < published
    rescue => e
      feed.logger.error(error: e.message, entry: to_h)
      return false
    end

    def tooted?
      return tooted.present?
    end

    def touch
      update(tooted: Time.now.to_s) unless tooted?
    rescue => e
      feed.logger.error(error: e.message, entry: to_h)
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
      entry = entry.to_h
      values = {
        feed: feed.hash,
        title: entry['title'],
        summary: entry['summary'],
        url: entry['url'],
        enclosure_url: entry['enclosure_url'],
      }
      return Entry.first(values) || Entry.create(values.merge(published: entry['published']))
    rescue => e
      feed.logger.error(error: e.message, entry: entry)
    end
  end
end
