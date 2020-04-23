require 'sequel/model'
require 'time'

module TomatoToot
  class Entry < Sequel::Model(:entry)
    alias to_h values

    def logger
      @logger ||= Logger.new
      return @logger
    end

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
      logger.info(entry: to_h)
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
  end
end
