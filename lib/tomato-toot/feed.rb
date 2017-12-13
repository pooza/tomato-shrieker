require 'feedjira'
require 'addressable/uri'
require 'digest/sha1'
require 'tomato-toot/url_shortener'

module TomatoToot
  class Feed
    attr_accessor :params

    def initialize (params)
      @params = params
      @params['source']['mode'] ||= 'title'
      @feed = Feedjira::Feed.fetch_and_parse(@params['source']['url'])
    end

    def prefix
      return (@params['prefix'] || @feed.title)
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
        body.push("[#{prefix}]")
        text = item[@params['source']['mode'].to_sym]
        next if (@params['source']['tag'] && !text.match("\##{@params['source']['tag']}"))
        body.push(text)
        url = item[:url]
        url = URLShortener.new.shorten(url) if @params['source']['shorten']
        body.push(url)
        yield body.join(' ')
      end
    end

    private
    def items
      return enum_for(__method__) unless block_given?
      @feed.entries.each.sort_by{|item| item.published.to_f}.each do |item|
        entry = {
          date: item.published,
          title: item.title,
          body: item.summary,
          url: create_url(item.url).to_s,
        }
        yield entry
      end
    end

    def create_url (src)
      dest = Addressable::URI.parse(src)
      unless dest.host
        dest = Addressable::URI.parse(@feed.url)
        dest.path = src
      end
      return dest
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
