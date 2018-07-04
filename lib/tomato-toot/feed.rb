require 'feedjira'
require 'digest/sha1'
require 'json'
require 'tomato-toot/config'
require 'tomato-toot/package'
require 'tomato-toot/bitly'
require 'tomato-toot/feed_entry'
require 'tomato-toot/mastodon'

module TomatoToot
  class Feed
    attr_reader :bitly
    attr_reader :mastodon

    def initialize(params)
      @config = Config.instance
      @params = params.clone

      Feedjira.configure do |config|
        config.user_agent = Package.user_agent
      end
      Feedjira.logger.level = ::Logger::FATAL
      @feed = Feedjira::Feed.fetch_and_parse(@params['source']['url'])

      @bitly = Bitly.new if shorten?
      @mastodon = Mastodon.new(@params['mastodon'])
    end

    def execute(options)
      raise 'empty' unless present?
      if options['silence']
        fetch.map(&:touch)
      elsif touched?
        fetch.map(&:toot)
      elsif entry = fetch.to_a.first
        entry.toot
      end
    end

    def fetch
      return enum_for(__method__) unless block_given?
      @feed.entries.each.sort_by{ |item| item.published.to_f}.reverse_each do |item|
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
      case @params['source']['mode']
      when 'body', 'summary'
        return 'summary'
      else
        return 'title'
      end
    end

    def tag
      return @params['source']['tag']
    end

    def visibility
      return (@params['visibility'] || 'public')
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
