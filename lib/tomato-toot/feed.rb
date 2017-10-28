require 'rss'
require 'json'
require 'digest/sha1'
require 'tomato-toot/url_shortener'

module TomatoToot
  class Feed
    def initialize (params, config = {})
      @config = config
      @params = params
      @params['mode'] ||= 'body'
      @feed = RSS::Parser.parse(self['url'])
    end

    def [] (key)
      return @params[key]
    end

    def touched?
      return File.exist?(timestamp_path)
    end

    def touch
      if items.present?
        time = items.to_a.last[:date].getlocal
        File.write(timestamp_path, time.strftime('%F %z %T'))
      end
    end

    def timestamp
      return Time.parse(File.read(timestamp_path))
    rescue
      return Time.parse('1970/10/01')
    end

    def items
      return enum_for(__method__) unless block_given?
      @feed.items.reverse.each do |item|
        entry = {
          date: item.pubDate,
          feed: self['name'],
          title: item.title,
          body: item.description,
          url: item.link,
        }
        yield entry
      end
    end

    def fetch (options = {})
      return enum_for(__method__, options) unless block_given?
      items do |item|
        next if (@params['tag'] && !item[:body].match(@params['tag']))
        next if (item[:date] <= timestamp)
        body = ["[#{item[:feed]}]"]
        case self['mode']
        when 'body'
          body.push(item[:body])
        when 'title'
          body.push(item[:title])
        else
          body.push('')
        end
        if self['shorten']
          body.push(shortener.shorten(item[:url]))
        else
          body.push(item[:url])
        end
        yield body.join(' ')
      end
    end

    private
    def timestamp_path
      return File.join(ROOT_DIR, 'tmp/timestamps', Digest::SHA1.hexdigest(self['url']))
    end

    def shortener
      unless @shortener
        @shortener = TomatoToot::URLShortener.new(@config)
      end
      return @shortener
    end
  end
end
