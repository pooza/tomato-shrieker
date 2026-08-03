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

    def shriek(template: nil, visibility: nil, attachments: nil, stats: @delivery_stats)
      params = {template:, visibility:, attachments:}.compact
      shriekers do |shrieker|
        if Environment.test?
          template&.to_s
          logger.info(source: id, shrieker: shrieker.class.to_s, message: 'skip (test)')
          next
        end
        shrieker.exec(params)
        stats&.record_success(shrieker)
      rescue Exception => e # rubocop:disable Lint/RescueException
        raise if e.is_a?(SignalException) || e.is_a?(SystemExit)
        klass = shrieker.class.to_s
        Sentry.capture_exception(e, tags: {source: id, shrieker: klass}) if Sentry.initialized?
        logger.error(source: id, shrieker: klass, error: e)
        stats&.record_error(shrieker, e)
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
      yield nostr if nostr?
      (self['/dest/hooks'] || []).each do |hook|
        yield WebhookShrieker.new(hook)
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

    def nostr
      unless @nostr
        return nil unless self['/dest/nostr/private_key']
        @nostr = NostrShrieker.new(@params.dig('dest', 'nostr'))
      end
      return @nostr
    rescue => e
      logger.error(source: id, error: e, nostr: 'initialization failed')
      return nil
    end

    def nostr?
      return nostr.present?
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

    def create_tags(status)
      container = Ginseng::Fediverse::TagContainer.new
      container.concat(tags.clone)
      container.concat(mulukhiya.search_hashtags(status)) if remote_tagging?
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

    def schedule_spec
      return {type: 'at', value: post_at} if post_at
      return {type: 'cron', value: cron} if cron
      return {type: 'every', value: period}
    end

    def monitored?
      return post_at.nil?
    end

    def next_run_at(after)
      return nil if post_at
      return Rufus::Scheduler.parse(cron).next_time(after).to_t if cron
      return after + Rufus::Scheduler.parse(period)
    end

    def monitor_grace_seconds
      return nil if post_at
      override = self['/monitor/tolerance']
      return Rufus::Scheduler.parse(override).to_i if override.is_a?(String)
      return override.to_i if override.is_a?(Numeric)
      return Config.instance['/monitor/default_tolerance_seconds']
    end

    # 無配信をどこまで許容するか (#1470)。
    # 未指定なら検知しない。chikanan のように年単位で正常に静かなソースがあるため、
    # 一律のデフォルトは置かず opt-in とする。
    def monitor_silence_tolerance_seconds
      return nil if post_at
      value = self['/monitor/silence_tolerance']
      return nil unless seconds = parse_duration(value)
      return seconds if seconds.positive?
      # 0 や負値は「常に沈黙」＝恒久 503 になるだけなので、検知しない側に倒す
      logger.warn(source: id, key: 'monitor/silence_tolerance', value:, message: 'not positive')
      return nil
    rescue => e
      # 不正値でこのソースだけを黙って無効化する。監視全体を巻き添えにしない。
      logger.error(source: id, key: 'monitor/silence_tolerance', value:, error: e)
      return nil
    end

    def parse_duration(value)
      return Rufus::Scheduler.parse(value).to_i if value.is_a?(String)
      return value.to_i if value.is_a?(Numeric)
      return nil
    end

    # 実際に配信できた最後の時刻。run_log は retention_days で刈られるので、
    # 取れなければソース種別ごとの永続データにフォールバックする。
    def last_delivered_at
      return delivery_history[:at]
    end

    # 'run_log' なら保持期間内の実配信、'fallback' はソース種別ごとの永続データ由来。
    def last_delivered_at_origin
      return delivery_history[:origin]
    end

    # run_log の保持期間より古い配信実績の当てになる代替。既定では持たない。
    def last_delivered_at_fallback
      return nil
    end

    def delivery_history
      @delivery_history ||= if at = SourceRunLog.last_delivered_at(id)
        {at:, origin: 'run_log'}
      elsif at = last_delivered_at_fallback
        {at:, origin: 'fallback'}
      else
        {at: nil, origin: nil}
      end
      return @delivery_history
    end

    # しきい値を超えて無配信が続いているか (#1470)。
    # 一度も配信実績が無い場合は「腐っている」と断定できないので false。
    def silent?
      return false unless tolerance = monitor_silence_tolerance_seconds
      return false unless last = last_delivered_at
      return Time.now > (last + tolerance)
    end

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
      return message.to_s.sanitize_status if fedi_sanitize?
      return message.to_s.sanitize
    end

    private

    def schedule(method, spec)
      job = Scheduler.instance.scheduler.send(method.to_sym, spec, {tag: id, overlap: false}) do
        exec_with_run_log(method, spec)
      end
      logger.info(source: id, job:, class: self.class.to_s, method.to_sym => spec)
      return job
    end

    def exec_with_run_log(method, spec)
      started_at = Time.now
      @delivery_stats = DeliveryStats.new
      logger.info(source: id, class: self.class.to_s, action: 'exec start', method.to_sym => spec)
      exec
      finalize_run_log(started_at)
    rescue Exception => e # rubocop:disable Lint/RescueException
      raise if e.is_a?(SignalException) || e.is_a?(SystemExit)
      SourceRunLog.record_error(id, started_at:, error: e, stats: @delivery_stats)
      Sentry.capture_exception(e, tags: {source: id}) if Sentry.initialized?
      logger.error(source: id, error: e)
    end

    def finalize_run_log(started_at)
      stats = @delivery_stats
      if stats.error?
        SourceRunLog.record_error(id, started_at:, error: stats.first_error, stats:)
        logger.error(
          source: id, class: self.class.to_s,
          action: 'exec end (delivery errors)', count: stats.error_count,
          delivered: stats.delivered_count
        )
      else
        SourceRunLog.record_success(id, started_at:, stats:)
        logger.info(
          source: id, class: self.class.to_s,
          action: 'exec end', delivered: stats.delivered_count
        )
      end
    end
  end
end
