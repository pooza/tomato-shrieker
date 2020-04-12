require 'sequel/model'

module TomatoToot
  class Entry < Sequel::Model(:entry)
    def logger
      @logger ||= Logger.new
      return @logger
    end

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

    def time
      @date ||= Time.parse(published)
      return @date
    end

    alias date time

    def body
      unless @body
        template = Template.new("toot.#{feed.template}")
        template[:feed] = feed
        template[:entry] = self
        @body = template.to_s
      end
      return @body
    end

    def enclosure_uri
      @enclosure ||= Ginseng::URI.parse(enclosure_url)
      @enclosure = feed.create_uri(@enclosure.path) unless @enclosure.absolute?
      return nil unless @enclosure.absolute?
      return @enclosure
    rescue
      return nil
    end

    alias enclosure enclosure_uri

    def uri
      @uri ||= feed.create_uri(url)
      return @uri
    end

    def tag?
      return feed.tag && body.match("\##{feed.tag}")
    end

    def tooted?
      return tooted.present?
    end

    def touch
      update(tooted: Time.now.to_s) unless tooted?
    end

    def post
      return if tooted
      toot if feed.mastodon
      feed.hooks do |hook|
        message = {text: body}
        message[:attachments] = [{image_url: enclosure.to_s}] if enclosure
        hook.say(message, :hash)
      rescue => e
        logger.error(e)
      end
      touch
      logger.info(entry: to_h)
    end

    def toot
      ids = []
      ids.push(feed.mastodon.upload_remote_resource(enclosure)) if enclosure
      response = feed.mastodon.toot(
        status: body,
        visibility: feed.visibility,
        media_ids: ids,
      )
      return response
    rescue => e
      logger.error(e)
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
