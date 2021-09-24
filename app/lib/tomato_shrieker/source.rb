require 'digest/sha1'

module TomatoShrieker
  class Source
    include Package

    def initialize(params)
      @params = params
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

    def exec
      raise Ginseng::ImplementError, "'#{__method__}' not implemented"
    end

    def shriek(params = {})
      shriekers do |shrieker|
        shrieker.exec(params)
      rescue => e
        logger.error(error: e)
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
      return Template.new(template_name)
    end

    def template_name
      return 'common'
    end

    def shriekers
      return enum_for(__method__) unless block_given?
      yield mastodon if mastodon?
      yield misskey if misskey?
      yield line if line?
      yield lemmy if lemmy?
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

    def line
      unless @line
        return nil unless user_id = self['/dest/line/user_id']
        return nil unless token = self['/dest/line/token']
        @line = LineShrieker.new(id: user_id, token: token)
      end
      return @line
    rescue => e
      logger.error(error: e, user_id: self['/dest/line/user_id'])
      return nil
    end

    def line?
      return line.present?
    end

    def lemmy
      unless @lemmy
        return nil unless self['/dest/lemmy/host']
        return nil unless self['/dest/lemmy/user_id']
        return nil unless self['/dest/lemmy/password']
        return nil unless self['/dest/lemmy/community_id']
        @lemmy = LemmyShrieker.new(@params.dig('dest', 'lemmy'))
      end
      return @lemmy
    end

    def lemmy?
      return lemmy.present?
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

    def tag_min_length
      return 2
    end

    def create_tags(status)
      container = Ginseng::Fediverse::TagContainer.new
      container.concat(tags.clone)
      container.concat(mulukhiya.search_hashtags(status)) if remote_tagging?
      container.select! {|v| tag_min_length < v.to_s.length}
      return container.create_tags
    end

    def remote_tagging?
      return mulukhiya.present? && (self['/dest/mulukhiya/tagging/enable'] == true)
    end

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
      config['/sources'].each do |entry|
        values = entry.key_flatten
        yield FeedSource.new(entry) if values['/source/feed']
        yield FeedSource.new(entry) if values['/source/url']
        yield CommandSource.new(entry) if values['/source/command']
        yield TextSource.new(entry) if values['/source/text']
        yield GoogleNewsSource.new(entry) if values['/source/news/url']
        yield GoogleNewsSource.new(entry) if values['/source/news/phrase']
        yield TweetTimelineSource.new(entry) if values['/source/tweet/account']
      end
    end

    def self.create(id)
      return all.find {|v| v.id == id}
    end
  end
end
