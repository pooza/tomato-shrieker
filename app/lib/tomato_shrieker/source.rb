require 'optparse'
require 'digest/sha1'

module TomatoShrieker
  class Source
    attr_reader :logger

    def initialize(params)
      @params = params
      @config = Config.instance
      @logger = Logger.new
    end

    def [](name)
      return @params.key_flatten[name] if name.start_with?('/')
      return @params[name]
    end

    def to_h
      return {'id' => id, 'class' => self.class.to_s}.merge(@params)
    end

    def id
      unless @id
        @id = self['/id']
        @id ||= self['/hash']
        @id ||= Digest::SHA1.hexdigest(@params.to_json)
      end
      return @id
    end

    alias hash id

    def exec(options = {})
      raise Ginseng::ImplementError, "'#{__method__}' not implemented"
    end

    def shriek(params = {})
      shriekers do |shrieker|
        shrieker.exec(params)
      end
    end

    def mulukhiya?
      return self['/dest/mulukhiya/enable'] == true
    end

    def bot_account?
      return self['/dest/account/bot'] unless self['/dest/account/bot'].nil?
      return false
    end

    alias bot? bot_account?

    def template
      return self['/dest/template'] || 'title'
    end

    def shriekers
      return enum_for(__method__) unless block_given?
      yield mastodon if mastodon?
      yield misskey if misskey?
      (self['/dest/hooks'] || []).each do |hook|
        yield WebhookShrieker.new(Ginseng::URI.parse(hook))
      end
    end

    def mastodon
      unless @mastodon
        return nil unless uri = self['/dest/mastodon/url']
        return nil unless token = self['/dest/mastodon/token']
        @mastodon = MastodonShrieker.new(uri, token)
        @mastodon.mulukhiya_enable = mulukhiya?
      end
      return @mastodon
    rescue => e
      logger.error(error: e, url: self['/dest/mastodon/url'])
      return nil
    end

    def mastodon?
      return mastodon.present?
    end

    def misskey
      unless @misskey
        return nil unless uri = self['/dest/misskey/url']
        return nil unless token = self['/dest/misskey/token']
        @misskey = MisskeyShrieker.new(uri, token)
        @misskey.mulukhiya_enable = mulukhiya?
      end
      return @misskey
    rescue => e
      logger.error(error: e, url: self['/dest/misskey/url'])
      return nil
    end

    def misskey?
      return misskey.present?
    end

    def mulukhiya
      return nil unless uri = Ginseng::URI.parse(self['/dest/mulukhiya/url'])
      @mulukhiya ||= MulukhiyaService.new(uri)
      return @mulukhiya
    rescue => e
      logger.error(error: e, url: self['/dest/mulukhiya/url'])
      return nil
    end

    def tags
      return (self['/dest/tags'] || []).map(&:to_hashtag)
    end

    alias toot_tags tags

    def visibility
      return self['/dest/visibility'] || 'public'
    end

    def prefix
      return self['/dest/prefix']
    end

    def post_at
      return self['/schedule/at']
    end

    alias at post_at

    def cron
      return nil if post_at
      return self['/schedule/cron']
    end

    def period
      return nil if post_at
      return nil if cron
      return self['/schedule/every'] || '5m'
    end

    alias every period

    def self.all
      return enum_for(__method__) unless block_given?
      Config.instance['/sources'].each do |entry|
        values = entry.key_flatten
        yield FeedSource.new(entry) if values['/source/url']
        yield TextSource.new(entry) if values['/source/text']
        yield CommandSource.new(entry) if values['/source/command']
      end
    end

    def self.create(id)
      all do |source|
        return source if source.id == id
      end
    end

    def self.exec_all
      options = ARGV.getopts('', 'silence', 'all')
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
