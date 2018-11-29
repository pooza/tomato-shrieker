require 'addressable/uri'

module TomatoToot
  class FeedEntry
    attr_reader :date
    attr_reader :body
    attr_reader :enclosure

    def initialize(feed, item)
      @feed = feed
      @date = item.published
      @body = create_body(item)
      begin
        @enclosure = Addressable::URI.parse(item.enclosure_url)
      rescue NoMethodError
        @enclosure = nil
      end
      @logger = Logger.new
    end

    def tag?
      return @feed.tag && @body.match("\##{@feed.tag}")
    end

    def outdated?
      return @date < @feed.timestamp
    end

    def tooted?
      return false unless @feed.touched?
      return false if @date != @feed.timestamp
      return @feed.status[:bodies].include?(@body)
    end

    def toot
      ids = []
      ids.push(@feed.mastodon.upload_remote_resource(@enclosure)) if @enclosure
      @feed.mastodon.toot(@body, {
        visibility: @feed.visibility,
        media_ids: ids,
      })
      touch
      @logger.info({mode: 'standalone', entry: {date: @date, body: @body}})
    end

    def touch
      values = @feed.status
      values[:bodies] = [] if @feed.timestamp != @date
      values[:date] = @date
      values[:bodies].push(@body)
      values[:bodies].uniq!
      @feed.status = values
    end

    private

    def create_body(item)
      body = []
      body.push("[#{@feed.prefix}]") unless @feed.bot_account?
      body.push(item.send(@feed.mode))
      body.push(create_uri(item.url).to_s)
      return body.join(' ')
    end

    def create_uri(href)
      uri = Addressable::URI.parse(href)
      unless uri.absolute?
        local_uri = uri
        uri = feed.uri.clone
        uri.path = local_uri.path
        uri.query = local_uri.query
        uri.fragment = local_uri.fragment
      end
      uri = @feed.bitly.shorten(uri) if @feed.shorten?
      return uri
    end
  end
end
