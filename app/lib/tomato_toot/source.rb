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
      return self['/mulukhiya/enable'] || true
    end

    def bot_account?
      return self['/bot_account'] || false
    end

    alias bot? bot_account?

    def template
      return self['/template'] || 'title'
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
      return self['/prefix']
    end

    def period
      return self['/period'] || self['/every'] || '5m'
    end

    alias every period

    def self.all
      return enum_for(__method__) unless block_given?
      (Config.instance['/sources'] || []).each do |entry|
        values = entry.key_flatten
        if values['/source/url']
          yield FeedSource.new(entry)
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
