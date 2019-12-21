require 'feedjira'
require 'digest/sha1'
require 'optparse'

module TomatoToot
  class Feed
    attr_reader :params

    def initialize(params)
      @config = Config.instance
      @params = params
      @params_flatten = Config.flatten('', params)
      @http = HTTP.new
    end

    def [](name)
      [@params_flatten, @params].each do |v|
        return v[name] unless v[name].nil?
      end
      return nil
    end

    def execute(options)
      raise Ginseng::NotFoundError, "Entries not found. (#{uri})" unless present?
      if options['silence']
        fetch.map(&:touch)
      elsif touched?
        fetch.map(&:post)
      elsif entry = fetch.to_a.first
        entry.post
      end
    end

    def fetch
      return enum_for(__method__) unless block_given?
      fetch_all do |entry|
        break if entry.outdated?
        next if tag && !entry.tag?
        next if entry.tooted?
        yield entry
      end
    end

    def fetch_all
      return enum_for(__method__) unless block_given?
      feedjira.entries.each.sort_by {|item| item.published.to_f}.reverse_each do |item|
        yield FeedEntry.new(self, item)
      end
    end

    def status
      unless @status
        @status = {}
        @status = JSON.parse(File.read(status_path), {symbolize_names: true}) if touched?
        @status[:bodies] ||= []
      end
      return @status
    end

    def status=(values)
      @status = nil
      File.write(status_path, JSON.pretty_generate(values))
    end

    def touched?
      return File.exist?(status_path)
    end

    def mulukhiya?
      return self['/mulukhiya/enable'] || true
    rescue
      return true
    end

    def bot_account?
      return self['/bot_account']
    end

    alias bot? bot_account?

    def shorten?
      return @config['/bitly/token'] && self['/shorten']
    rescue
      return false
    end

    def template
      return self['/template'] || 'default'
    end

    def present?
      return feedjira.entries.present?
    end

    def uri
      @uri ||= Ginseng::URI.parse(self['/source/url'])
      raise Ginseng::ConfigError, "Invalid feed URL '#{@uri}'" unless @uri.absolute?
      return @uri
    end

    def bitly
      @bitly ||= Bitly.new if shorten?
      return @bitly
    end

    def mastodon
      return nil unless self['/mastodon/url'].present?
      return nil unless self['/mastodon/token'].present?
      unless @mastodon
        @mastodon = Mastodon.new(self['/mastodon/url'], self['/mastodon/token'])
        @mastodon.mulukhiya_enable = mulukhiya?
      end
      return @mastodon
    end

    def webhooks
      return [] unless self['/hooks'].present?
      return self['/hooks'].map do |hook|
        Ginseng::URI.parse(hook)
      end
    end

    alias hooks webhooks

    def feedjira
      @feedjira ||= Feedjira.parse(@http.get(uri).body)
      return @feedjira
    end

    def mode
      case self['/source/mode']
      when 'body', 'summary'
        return 'summary'
      else
        return 'title'
      end
    rescue
      return 'title'
    end

    def toot_tags
      return self['/toot/tags'].map do |tag|
        Mastodon.create_tag(tag)
      end
    rescue
      return []
    end

    def tag
      return self['/source/tag']
    rescue
      return nil
    end

    def visibility
      return (self['/visibility'] || 'public')
    rescue
      return 'public'
    end

    def prefix
      return (self['/prefix'] || feedjira.title)
    end

    def timestamp
      return Time.parse(status[:date])
    rescue
      return Time.parse('1970/01/01')
    end

    def status_path
      @status_path ||= File.join(
        Environment.dir,
        'tmp/timestamps',
        "#{Digest::SHA1.hexdigest(@params_flatten.to_s)}.json",
      )
      return @status_path
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
        logger.info(feed.params)
        feed.execute(options)
      rescue => e
        e = Ginseng::Error.create(e)
        e.package = Package.full_name
        message = e.to_h.merge(feed: feed.params)
        Slack.broadcast(message)
        logger.error(message)
        next
      end
    end
  end
end
