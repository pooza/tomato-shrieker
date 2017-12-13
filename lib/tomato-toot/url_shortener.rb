require 'json'
require 'addressable/uri'
require 'httparty'
require 'tomato-toot/config'

module TomatoToot
  class URLShortener
    def initialize
      @config = Config.new
    end

    def shorten (url)
      return HTTParty.post(service_url, {
        body: {longUrl: url}.to_json,
        headers: {'Content-Type' => 'application/json'},
      })['id']
    end

    private
    def service_url
      url = Addressable::URI.parse(@config['application']['services']['url_shortener']['url'])
      query = url.query_values || {}
      query['key'] = api_key
      url.query_values = query
      return url.to_s
    end

    def api_key
      return @config['local']['services']['url_shortener']['api_key']
    end
  end
end
