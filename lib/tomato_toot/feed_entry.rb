require 'addressable/uri'

module TomatoToot
  class FeedEntry
    def initialize(feed, item)
      @feed = feed
      @item = item
      @logger = Logger.new
    end

    def tag?
      return @feed.tag && body.match("\##{@feed.tag}")
    end

    def outdated?
      return date < @feed.timestamp
    end

    def tooted?
      return false unless @feed.touched?
      return false if date != @feed.timestamp
      return @feed.status[:bodies].include?(body)
    end

    def toot
      ids = []
      ids.push(@feed.mastodon.upload_remote_resource(enclosure)) if enclosure
      @feed.mastodon.toot({
        status: body,
        visibility: @feed.visibility,
        media_ids: ids,
      })
      touch
      @logger.info({mode: 'standalone', entry: {date: date, body: body}})
    end

    def touch
      values = @feed.status
      values[:bodies] = [] if @feed.timestamp != date
      values[:date] = date
      values[:bodies].push(body)
      values[:bodies].uniq!
      @feed.status = values
    end

    def date
      return @item.published
    end

    def body
      unless @body
        body = []
        body.push("[#{@feed.prefix}]") unless @feed.bot_account?
        body.push(@item.send(@feed.mode))
        body.concat(@feed.toot_tags)
        body.push(create_uri(@item.url).to_s)
        @body = body.join(' ')
      end
      return @body
    end

    def enclosure
      @enclosure ||= Addressable::URI.parse(@item.enclosure_url)
      @enclosure = create_uri(@enclosure.path) unless @enclosure.absolute?
      return nil unless @enclosure.absolute?
      return @enclosure
    rescue
      return nil
    end

    private

    def create_uri(href)
      uri = Addressable::URI.parse(href)
      uri.path ||= @feed.uri.path
      uri.query ||= @feed.uri.query
      uri.fragment ||= @feed.uri.fragment
      uri = @feed.bitly.shorten(uri) if @feed.shorten?
      return uri
    end
  end
end
