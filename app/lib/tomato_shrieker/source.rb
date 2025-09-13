require 'digest/sha1'

module TomatoShrieker
  class Source # rubocop:disable Metrics/ClassLength
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
      @id ||= self['/id'] || Digest::SHA1.hexdigest(@params.to_json)
      return @id
    end

    alias hash id

    def exec
      raise Ginseng::ImplementError, "'#{__method__}' not implemented"
    end

    def register
      return if disable?
      return schedule(:at, post_at) if post_at
      return schedule(:cron, cron) if cron
      return schedule(:every, every)
    end

    def shriek(params = {})
      shriekers do |shrieker|
        shrieker.exec(params)
      rescue => e
        logger.error(source: id, error: e)
      end
    end

    def disable?
      return self['/disable'] == true
    end

    def sanitize_mode
      return :fedi if self['/dest/sanitize'].nil?
      return self['/dest/sanitize'].to_sym
    end

    def fedi_sanitize?
      return sanitize_mode == :fedi
    end

    def mulukhiya?
      return self['/dest/mulukhiya/enable'] == true
    end

    def test?
      return Environment.development? || self['/test'] == true
    end

    def bot?
      return self['/dest/account/bot'] unless self['/dest/account/bot'].nil?
      return true
    end

    def templates
      @templates ||= {
        default: Template.new(self['/dest/template'] || 'common'),
        piefed: Template.new(self['/dest/piefed/template'] || self['/dest/template'] || 'common'),
      }
      return @templates
    end

    def create_template(type = :default, status = nil)
      template = templates[type]
      template[:source] = self
      template[:status] = status
      return template
    end

    def spoiler_text
      @spoiler_text ||= self['/dest/spoiler_text']
      return @spoiler_text
    end

    def clear
    end

    def shriekers
      return enum_for(__method__) unless block_given?
      yield mastodon if mastodon?
      yield misskey if misskey?
      yield line if line?
      yield piefed if piefed?
      (self['/dest/hooks'] || []).each do |hook|
        yield WebhookShrieker.new(Ginseng::URI.parse(hook))
      end
    end

    def webhook?
      return (self['/dest/hooks'] || []).present?
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
      logger.error(source: id, error: e, url: self['/dest/mastodon/url'])
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
      logger.error(source: id, error: e, url: self['/dest/misskey/url'])
      return nil
    end

    def misskey?
      return misskey.present?
    end

    def line
      unless @line
        return nil unless user_id = self['/dest/line/user_id']
        return nil unless token = self['/dest/line/token']
        @line = LineShrieker.new(id: user_id, token:)
      end
      return @line
    rescue => e
      logger.error(source: id, error: e, user_id: self['/dest/line/user_id'])
      return nil
    end

    def line?
      return line.present?
    end

    def piefed
      unless @piefed
        return nil unless self['/dest/piefed/host']
        return nil unless self['/dest/piefed/user_id']
        return nil unless self['/dest/piefed/password']
        return nil unless self['/dest/piefed/community_id']
        @piefed = PiefedShrieker.new(@params.dig('dest', 'piefed'))
      end
      return @piefed
    rescue => e
      logger.error(source: id, error: e, piefed: self['/dest/piefed/host'])
      return nil
    end

    def piefed?
      return piefed.present?
    end

    def mulukhiya
      return nil unless uri = Ginseng::URI.parse(self['/dest/mulukhiya/url'])
      @mulukhiya ||= MulukhiyaService.new(uri)
      return @mulukhiya
    rescue => e
      logger.error(source: id, error: e, url: self['/dest/mulukhiya/url'])
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
      return self['/schedule/cron'] || default_cron
    end

    def default_cron
      return nil
    end

    def period
      return nil if post_at
      return nil if cron
      return self['/schedule/every'] || default_period
    end

    def default_period
      return '5m'
    end

    alias every period

    def self.all
      return enum_for(__method__) unless block_given?
      config['/sources'].each do |entry|
        source_entry = entry.key_flatten
        classes.each do |source_class|
          yield source_class[:class].new(entry) if source_entry[source_class[:config]]
        end
      end
    end

    def self.classes
      return config['/source/classes'].map do |entry|
        source_class = entry.deep_symbolize_keys
        source_class[:class] = "TomatoShrieker::#{source_class[:class]}".constantize
        source_class
      end
    end

    def self.create(id)
      return all.find {|v| v.id == id}
    end

    def fedi_sanitize(message)
      return fedi_sanitize? ? message.to_s.sanitize_status : message.to_s.sanitize
    end

    private

    def schedule(method, spec)
      job = Scheduler.instance.send(method.to_sym, spec, {tag: id}) do
        logger.info(source: id, class: self.class.to_s, action: 'exec start', method.to_s => spec)
        exec
        logger.info(source: id, class: self.class.to_s, action: 'exec end')
      rescue => e
        logger.error(source: id, error: e)
      end
      logger.info(source: id, job:, class: self.class.to_s, method.to_s => spec)
      return job
    end
  end
end
