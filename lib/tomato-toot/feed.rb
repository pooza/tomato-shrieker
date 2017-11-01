require 'rss'
require 'digest/sha1'
require 'tomato-toot/url_shortener'

module TomatoToot
  class Feed
    attr_accessor :params

    def initialize (params, config = {})
      @params = params
      @config = config
      @params['source']['mode'] ||= 'title'
      @feed = RSS::Parser.parse(@params['source']['url'])
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

    def fetch (options = {})
      return enum_for(__method__, options) unless block_given?
      items do |item|
        next if (item[:date] <= timestamp)
        body = []
        body.push("[#{@params['prefix']}]") if @params['prefix']
        text = item[@params['source']['mode'].to_sym]
        next if (@params['source']['tag'] && !text.match("\##{@params['source']['tag']}"))
        body.push(text)
        url = item[:url]
        url = shortener.shorten(url) if @params['source']['shorten']
        body.push(url)
        yield body.join(' ')
      end
    end

    private
    def items
      return enum_for(__method__) unless block_given?
      @feed.items.sort_by{|item| item.pubDate.to_f}.each do |item|
        entry = {
          date: item.pubDate,
          title: item.title,
          body: item.description,
          url: item.link,
        }
        yield entry
      end
    end

    def timestamp_path
      return File.join(
        ROOT_DIR,
        'tmp/timestamps',
        Digest::SHA1.hexdigest(@params.to_s),
      )
    end

    def shortener
      unless @shortener
        @shortener = TomatoToot::URLShortener.new(@config)
      end
      return @shortener
    end
  end
end
