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
      @zone = values['zone']
      @feed = RSS::Parser.parse(values['url'])
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

    def title
      return @feed.channel.title
    end

    def items
      return enum_for(__method__) unless block_given?
      @feed.items.reverse.each do |item|
        entry = {
          date: item.pubDate,
          feed: @name,
          title: item.title,
          body: item.description,
          url: item.link,
        }
        yield entry
      end
    end

    def bodies (options = {})
      return enum_for(__method__, options) unless block_given?
      items.each do |item|
        next if (options['tag'] && !item[:body].match("##{options['tag']}"))
        next if (!options['all'] && (item[:date] <= timestamp))
        body = ["[#{item[:feed]}]", item[:body]]
        if (options['shorten'])
          body.push(shortener.shorten(item[:url]))
        else
          body.push(item[:url])
        end
        yield body.join(' ')
      end
    end

    private
    def timestamp_path
      return File.join(ROOT_DIR, 'tmp/timestamps', "#{Digest::SHA1.hexdigest(@url)}.json")
    end

    def shortener
      unless @shortener
        @shortener = TomatoToot::URLShortener.new(@config)
      end
      return @shortener
    end
  end
end
