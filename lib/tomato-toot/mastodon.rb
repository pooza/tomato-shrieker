require 'addressable/uri'
require 'httparty'
require 'json'
require 'tomato-toot/package'

module TomatoToot
  class Mastodon
    def initialize(params)
      @params = params.clone
    end

    def toot(text, options = {})
      values = options.clone
      values[:status] = text
      url = Addressable::URI.parse(@params['url'])
      url.path = '/api/v1/statuses'

      return HTTParty.post(url, {
        body: values.to_json,
        headers: {
          'Content-Type' => 'application/json',
          'User-Agent' => Package.user_agent,
          'Authorization' => "Bearer #{@params['token']}",
          'X-Mulukhiya' => 'pass through',
        },
        ssl_ca_file: ENV['SSL_CERT_FILE'],
      })
    end
  end
end
