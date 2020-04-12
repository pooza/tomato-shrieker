require 'feedjira'
require 'digest/sha1'
require 'optparse'

module TomatoToot
  class Feed
    def initialize(params)
      @config = Config.instance
      @params = params
      @http = HTTP.new
      @http.base_uri = uri
      @logger = Logger.new
    end

    def [](name)
      [@params.key_flatten, @params].each do |v|
        return v[name] unless v[name].nil?
      end
      return nil
    end

    def to_h
      return {hash: hash}.merge(@params)
    end

    def hash
      return Digest::SHA1.hexdigest(@params.to_json)
    end

    def execute(options)
      raise Ginseng::NotFoundError, "Entries not found. (#{uri})" unless present?
      Sequel.connect(Environment.dsn).transaction do
        if options['silence']
          fetch.to_a.map(&:touch)
        else
          fetch.to_a.map(&:post)
        end
      end
    rescue => e
      @logger.error(e)
    end

    def fetch
      return enum_for(__method__) unless block_given?
      feedjira.entries.each.sort_by {|item| item.published.to_f}.each do |entry|
        yield Entry.get(self, entry)
      rescue => e
        @logger.error(Ginseng::Error.create(e).to_h.merge(entry: entry))
      end
    end

    def mulukhiya?
      return self['/mulukhiya/enable'] || true
    rescue
      return true
    end

    def bot_account?
      return self['/bot_account'] || false
    end

    alias bot? bot_account?

    def template
      return self['/template'] || 'default'
    end

    def present?
      return feedjira.entries.present?
    end

    def uri
      return nil unless uri = Ginseng::URI.parse(self['/source/url'])
      return nil unless uri.absolute?
      return uri
    end

    def mastodon
      unless @mastodon
        return nil unless uri.present?
        return nil unless token = self['/mastodon/token']
        @mastodon = Mastodon.new(uri, token)
        @mastodon.mulukhiya_enable = mulukhiya?
      end
      return @mastodon
    end

    def webhooks
      return enum_for(__method__) unless block_given?
      (self['/hooks'] || []).each do |hook|
        yield Slack.new(Ginseng::URI.parse(hook))
      end
    end

    alias hooks webhooks

    def feedjira
      @feedjira ||= Feedjira.parse(@http.get(uri).body)
      return @feedjira
    end

    def mode
      unless @mode
        @mode = self['/source/mode'] || 'title'
        @mode = 'summary' if @mode == 'body'
      end
      return @mode
    end

    def tags
      return self['/toot/tags'].map do |tag|
        Mastodon.create_tag(tag)
      end
    rescue => e
      @logger.error(e)
      return []
    end

    alias toot_tags tags

    def tag
      return self['/source/tag']
    rescue
      return nil
    end

    def visibility
      return self['/visibility'] || 'public'
    rescue
      return 'public'
    end

    def prefix
      return self['/prefix'] || feedjira.title
    end

    def create_uri(href)
      uri = @http.create_uri(href)
      uri.fragment ||= self.uri.fragment
      return uri
    end

    def self.all
      return enum_for(__method__) unless block_given?
      Config.instance['/entries'].each do |entry|
        next unless entry['source']
        next if entry['webhook']
        yield Feed.new(entry)
      end
    end

    def self.crawl_all
      logger = Logger.new
      options = ARGV.getopts('', 'silence')
      all do |feed|
        logger.info(feed: feed.to_h)
        feed.execute(options)
      rescue => e
        e = Ginseng::Error.create(e)
        e.package = Package.full_name
        message = e.to_h.merge(feed: feed.to_h)
        Slack.broadcast(message)
        logger.error(message)
      end
    end
  end
end
