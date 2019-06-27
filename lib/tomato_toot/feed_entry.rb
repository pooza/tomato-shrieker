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

    def post
      toot if @feed.mastodon
      @feed.hooks.map do |hook|
        message = {text: body}
        message[:attachments] = [{image_url: enclosure.to_s}] if enclosure
        Slack.new(hook).say(message, :hash)
      rescue => e
        @logger.error(e)
      end
      touch
      @logger.info({entry: {date: date, body: body}})
    end

    def toot
      ids = []
      begin
        ids.push(@feed.mastodon.upload_remote_resource(enclosure)) if enclosure
      rescue Ginseng::GatewayError => e
        @logger.error(e)
      end
      return @feed.mastodon.toot({
        status: body,
        visibility: @feed.visibility,
        media_ids: ids,
      })
    end

    def touch
      values = @feed.status
      values[:bodies] = [] if @feed.timestamp != date
      values[:date] = date
      values[:bodies].push(body)
      values[:bodies].uniq!
      @feed.status = values
    end

    def title
      return @item.title
    end

    def summary
      return @item.summary
    end

    def date
      return @item.published
    end

    def body
      unless @body
        template = Template.new("toot.#{@feed.template}")
        template[:feed] = @feed
        template[:entry] = self
        @body = template.to_s
      end
      return @body
    end

    def enclosure_uri
      @enclosure ||= Ginseng::URI.parse(@item.enclosure_url)
      @enclosure = create_uri(@enclosure.path) unless @enclosure.absolute?
      return nil unless @enclosure.absolute?
      return @enclosure
    rescue
      return nil
    end

    alias enclosure enclosure_uri

    def uri
      @uri ||= create_uri(@item.url)
      return @uri
    end

    private

    def create_uri(href)
      uri = Ginseng::URI.parse(href)
      uri.path ||= @feed.uri.path
      uri.query ||= @feed.uri.query
      uri.fragment ||= @feed.uri.fragment
      uri = @feed.bitly.shorten(uri) if @feed.shorten?
      return uri
    end
  end
end
