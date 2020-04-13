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

    def tooted?
      return tooted.present?
    end

    def touch
      update(tooted: Time.now.to_s) unless tooted?
    end

    def post
      return false if tooted?
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

    def self.get(feed, item)
      item = item.to_h
      values = {
        feed: feed.hash,
        title: item['title'],
        summary: item['summary'],
        url: item['url'],
        enclosure_url: item['enclosure_url'],
        published: item['published'],
      }
      return Entry.first(values) || Entry.create(values)
    end
  end
end
