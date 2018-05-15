require 'feedjira'
require 'digest/sha1'
require 'mastodon'
require 'json'
require 'tomato-toot/config'
require 'tomato-toot/package'
require 'tomato-toot/bitly'
require 'tomato-toot/feed_entry'

module TomatoToot
  class Feed
    attr_reader :bitly
    attr_reader :mastodon

    def initialize(params)
      @config = Config.instance
      @params = params.clone

      case @params['source']['mode']
      when 'body', 'summary'
        @params['source']['mode'] = 'summary'
      else
        @params['source']['mode'] = 'title'
      end

      Feedjira.configure do |config|
        config.user_agent = "#{Package.full_name} #{Package.url}"
      end
      Feedjira.logger.level = ::Logger::FATAL
      @feed = Feedjira::Feed.fetch_and_parse(@params['source']['url'])

      @bitly = Bitly.new if shorten?
      @mastodon = Mastodon::REST::Client.new({
        base_url: @params['mastodon']['url'],
        bearer_token: @params['mastodon']['token'],
      })
    end

    def execute(options)
      raise 'empty' unless present?
      if options['silence']
        fetch.map(&:touch)
      elsif touched?
        fetch.map(&:toot)
      elsif present?
        fetch.to_a.first.toot
      end
    end

    def fetch
      return enum_for(__method__) unless block_given?
      @feed.entries.each.sort_by{ |item| item.published.to_f}.reverse.each do |item|
        entry = FeedEntry.new(self, item)
        break if entry.outdated?
        next if tag && !entry.tag?
        next if entry.tooted?
        yield entry
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

    def bot_account?
      return @params['bot_account']
    end

    def shorten?
      return @config['local']['bitly'] && @params['shorten']
    end

    def present?
      return @feed.entries.present?
    end

    def url
      return @params['source']['url']
    end

    def mode
      return @params['source']['mode']
    end

    def tag
      return @params['source']['tag']
    end

    def prefix
      return (@params['prefix'] || @feed.title)
    end

    def timestamp
      return Time.parse(status[:date])
    rescue
      return Time.parse('1970/01/01')
    end

    def status_path
      return File.join(
        ROOT_DIR,
        'tmp/timestamps',
        "#{Digest::SHA1.hexdigest(@params.to_s)}.json",
      )
    end
  end
end
