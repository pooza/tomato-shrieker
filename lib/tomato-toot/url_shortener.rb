require 'json'
require 'uri'
require 'addressable/uri'
require 'httparty'

module TomatoToot
  class URLShortener
    def initialize (config = {})
      @config = config
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
      url.query_values['key'] = api_key
      return url.to_s
    end

    def api_key
      return @config['local']['services']['url_shortener']['api_key']
    end
  end
end
