require 'feedjira'
require 'digest/sha1'
require 'optparse'
require 'sanitize'

module TomatoToot
  class Feed
    attr_reader :logger

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
      if options['silence']
        touch
      elsif touched?
        fetch do |entry|
          entry.post
        rescue => e
          logger.error(e)
        end
      elsif entry = fetch.to_a.last
        entry.post
        touch
      end
    rescue => e
      e = Ginseng::Error.create(e)
      e.package = Package.full_name
      Slack.broadcast(e)
      logger.error(e)
    end

    alias crawl execute

    alias exec execute

    def time
      unless @time
        records = Entry.dataset
          .select(:published)
          .where(feed: hash)
          .order(Sequel.desc(:published))
          .limit(1)
        @time = records.first&.published
      end
      return @time
    end

    def touched?
      return time.present?
    end

    def touch
      feedjira.entries.map {|v| create_entry(v)}
    end

    def fetch
      return enum_for(__method__) unless block_given?
      feedjira.entries.sort_by {|entry| entry.published.to_f}.each do |v|
        entry = create_entry(v)
        yield entry if entry
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

    def recent?
      return self['/recent'] || false
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
        return nil unless uri = self['/mastodon/url']
        return nil unless token = self['/mastodon/token']
        @mastodon = Mastodon.new(uri, token)
        @mastodon.mulukhiya_enable = mulukhiya?
      end
      return @mastodon
    end

    def mastodon?
      return mastodon.present?
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
      return (self['/toot/tags'] || []).map do |tag|
        Mastodon.create_tag(tag)
      end
    end

    alias toot_tags tags

    def visibility
      return self['/visibility'] || 'public'
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

    def self.exec_all
      options = ARGV.getopts('', 'silence')
      threads = []
      Sequel.connect(Environment.dsn).transaction do
        all do |feed|
          threads.push(Thread.new {feed.exec(options)})
        end
        threads.map(&:join)
      end
    end

    private

    def create_entry(entry)
      h = entry.to_h
      return Entry.create(
        feed: hash,
        title: Sanitize.clean(h['title']),
        summary: Sanitize.clean(h['summary']),
        url: h['url'],
        enclosure_url: h['enclosure_url'],
        published: h['published'] || Time.now,
      )
    rescue Sequel::UniqueConstraintViolation, Sequel::NoExistingObject
      return nil
    rescue => e
      logger.error(error: e.message, entry: entry)
      return nil
    end
  end
end
