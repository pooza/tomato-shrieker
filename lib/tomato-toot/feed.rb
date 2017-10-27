require 'rss'
require 'json'
require 'digest/sha1'
require 'tomato-toot/url_shortener'

module TomatoToot
  class Feed
    def initialize (values, config = {})
      @config = config
      @name = values['name']
      @url = values['url']
      @feed = RSS::Parser.parse(values['url'])
    end

    def touch
      if (newest = @feed.items.first)
        File.write(timestamp_path, {date: newest.pubDate + (tz_offset * 3600)}.to_json)
      end
    end

    def timestamp
      return Time.parse(File.read(timestamp_path)) if File.exist?(timestamp_path)
      return Time.parse('1970/10/01')
    end

    def title
      return @feed.channel.title
    end

    def items
      return enum_for(__method__) unless block_given?
      shortener = TomatoToot::URLShortener.new(@config)
      @feed.items.reverse.each do |item|
        entry = {
          date: item.pubDate + (tz_offset * 3600),
          feed: @name,
          title: item.title,
          body: item.description,
          url: shortener.shorten(item.link),
        }
        yield entry
      end
    end

    def bodies (options = {})
      return enum_for(__method__, options) unless block_given?
      items.each do |item|
        if (options['all'] || (timestamp < item[:date]))
          yield ["[#{item[:feed]}]", item[:body], item[:url]].join(' ')
        end
      end
    end

    private
    def timestamp_path
      return File.join(ROOT_DIR, 'tmp/timestamps', "#{Digest::SHA1.hexdigest(@url)}.json")
    end

    def tz_offset
      return (@config['local']['tz_offset'].to_i || 0)
    end
  end
end
