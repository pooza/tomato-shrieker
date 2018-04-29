require 'feedjira'
require 'addressable/uri'
require 'digest/sha1'
require 'json'
require 'mastodon'
require 'tomato-toot/config'
require 'tomato-toot/package'
require 'tomato-toot/bitly'
require 'tomato-toot/logger'

module TomatoToot
  class Feed
    def initialize (params)
      @params = params
      @params['source']['mode'] ||= 'title'
      @logger = Logger.new

      Feedjira.configure do |config|
        config.user_agent = "#{Package.full_name} #{Package.url}"
      end
      Feedjira.logger.level = ::Logger::FATAL
      @feed = Feedjira::Feed.fetch_and_parse(@params['source']['url'])

      @mastodon = Mastodon::REST::Client.new({
        base_url: params['mastodon']['url'],
        bearer_token: params['mastodon']['token'],
      })
      @bitly = Bitly.new if Config.instance['local']['bitly']
    end

    def touched?
      return File.exist?(status_path)
    end

    def present?
      return items.present?
    end

    def toot (entry, options)
      unless options['silence']
        @mastodon.create_status(entry[:body])
        @logger.info({entry: entry, options: options})
      end
      touch(entry)
    end

    def fetch
      return enum_for(__method__) unless block_given?
      items.each do |item|
        next if (item[:date] < timestamp)
        body = []
        body.push("[#{prefix}]") unless @params['bot_account']
        text = item[@params['source']['mode'].to_sym]
        next if (@params['source']['tag'] && !text.match("\##{@params['source']['tag']}"))
        body.push(text)
        url = item[:url]
        url = Bitly.new.shorten(url) if @params['shorten']
        body.push(url)
        values = {date: item[:date], body: body.join(' ')}
        next if tooted?(values)
        yield values
      end
    end

    private
    def items
      unless @items
        @items = []
        @feed.entries.each.sort_by{|item| item.published.to_f}.each do |item|
          @items.push({
            date: item.published,
            title: item.title,
            body: item.summary,
            url: create_url(item.url).to_s,
          })
        end
        @items.reverse!
      end
      return @items
    end

    def touch (entry)
      if touched?
        status = JSON.parse(File.read(status_path))
        if (Time.parse(status['date']) == entry[:date])
          status['bodies'] ||= []
        else
          status['date'] = entry[:date]
          status['bodies'] = []
        end
        status['bodies'].push(entry[:body])
      else
        status = {date: entry[:date], bodies: [entry[:body]]}
      end
      File.write(status_path, JSON.pretty_generate(status))
    end

    def prefix
      return (@params['prefix'] || @feed.title)
    end

    def timestamp
      return Time.parse(JSON.parse(File.read(status_path))['date'])
    rescue => e
      return Time.parse('1970/01/01')
    end

    def tooted? (entry)
      if touched?
        status = JSON.parse(File.read(status_path))
        status['bodies'] ||= []
        return (entry[:date] == status['date']) && status['bodies'].include?(entry[:body])
      end
      return false
    end

    def create_url (href)
      url = Addressable::URI.parse(href)
      unless url.scheme
        local_url = url
        url = Addressable::URI.parse(@feed.url)
        url.path = local_url.path
        url.query = local_url.query
        url.fragment = local_url.fragment
      end
      return url
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
