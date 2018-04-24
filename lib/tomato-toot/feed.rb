require 'feedjira'
require 'addressable/uri'
require 'digest/sha1'
require 'json'
require 'mastodon'
require 'tomato-toot/config'
require 'tomato-toot/package'
require 'tomato-toot/bitly'

module TomatoToot
  class Feed
    attr_accessor :params

    def initialize (params)
      @params = params
      @params['source']['mode'] ||= 'title'

      Feedjira.configure do |config|
        config.user_agent = "#{Package.full_name} #{Package.url}"
      end
      @feed = Feedjira::Feed.fetch_and_parse(@params['source']['url'])

      @mastodon = Mastodon::REST::Client.new({
        base_url: params['mastodon']['url'],
        bearer_token: params['mastodon']['token'],
      })
      @bitly = Bitly.new if Config.instance['local']['bitly']
    end

    def prefix
      return (@params['prefix'] || @feed.title)
    end

    def touched?
      return File.exist?(timestamp_path)
    end

    def present?
      return items.present?
    end

    def touch
      File.write(timestamp_path, updated_at.strftime('%F %z %T')) if present?
    end

    def toot (entry)
      File.write(create_toot_path(entry), entry.to_json)
      @mastodon.create_status(entry[:body])
    end

    def timestamp
      return Time.parse(File.read(timestamp_path))
    rescue
      return Time.parse('1970/01/01')
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
      end
      return @items
    end

    def tooted? (entry)
      return File.exist?(create_toot_path(entry))
    end

    def updated_at
      if present?
        return items.last[:date].getlocal
      else
        return nil
      end
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

    def create_toot_path (entry)
      return File.join(
        ROOT_DIR,
        'tmp/tooted',
        Digest::SHA1.hexdigest([@params, entry].to_json),
      )
    end

    def timestamp_path
      return File.join(
        ROOT_DIR,
        'tmp/timestamps',
        Digest::SHA1.hexdigest(@params.to_s),
      )
    end
  end
end
