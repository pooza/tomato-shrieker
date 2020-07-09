require 'optparse'
require 'digest/sha1'

module TomatoToot
  class Source
    attr_reader :logger

    def initialize(params)
      @params = params
      @config = Config.instance
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

    def exec(options = {})
      raise Ginseng::ImplementError, "'#{__method__}' not implemented"
    end

    def mulukhiya?
      return self['/dest/mulukhiya/enable'] unless self['/def/mulukhiya/enable'].nil?
      return self['/mulukhiya/enable'] unless self['/mulukhiya/enable'].nil?
      return true
    end

    def bot_account?
      return self['/dest/account/bot'] unless self['/dest/account/bot'].nil?
      return self['/bot_account'] unless self['/bot_account'].nil?
      return false
    end

    alias bot? bot_account?

    def template
      return self['/dest/template'] || self['/template'] || 'title'
    end

    def mastodon
      unless @mastodon
        return nil unless uri = self['/dest/mastodon/url'] || self['/mastodon/url']
        return nil unless token = self['/dest/mastodon/token'] || self['/mastodon/token']
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
      (self['/dest/hooks'] || self['/hooks'] || []).each do |hook|
        yield Slack.new(Ginseng::URI.parse(hook))
      end
    end

    alias hooks webhooks

    def tags
      return (self['/dest/tags'] || self['/toot/tags'] || []).map do |tag|
        Mastodon.create_tag(tag)
      end
    end

    alias toot_tags tags

    def visibility
      return self['/visibility'] || 'public'
    end

    def prefix
      return self['/dest/prefix'] || self['/prefix']
    end

    def post_at
      return self['/schedule/at'] || self['/post_at'] || self['/at']
    end

    alias at post_at

    def cron
      return nil if post_at
      return self['/schedule/cron'] || self['/cron']
    end

    def period
      return nil if post_at
      return nil if cron
      return self['/schedule/every'] || self['/period'] || self['/every'] || '5m'
    end

    alias every period

    def self.all
      return enum_for(__method__) unless block_given?
      Config.instance['/sources'].each do |entry|
        values = entry.key_flatten
        if values['/source/url']
          yield FeedSource.new(entry)
        elsif values['/source/text']
          yield TextSource.new(entry)
        elsif values['/source/command']
          yield CommandSource.new(entry)
        end
      end
    end

    def self.create(hash)
      all do |feed|
        return feed if feed.hash == hash
      end
    end

    def self.exec_all
      options = ARGV.getopts('', 'silence')
      threads = []
      Sequel.connect(Environment.dsn).transaction do
        all do |source|
          threads.push(Thread.new {source.exec(options)})
        rescue => e
          e = Ginseng::Error.create(e)
          e.package = Package.full_name
          Slack.broadcast(e)
          source.logger.error(e)
        end
        threads.map(&:join)
      end
    end
  end
end
