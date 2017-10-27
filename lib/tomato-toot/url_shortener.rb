require 'json'
require 'uri'
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
      url = URI.parse(@config['application']['services']['url_shortener']['url'])
      url.query = "key=#{api_key}"
      return url.to_s
    end

    def api_key
      return @config['local']['services']['url_shortener']['api_key']
    end
  end
end
