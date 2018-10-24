require 'addressable/uri'
require 'httparty'
require 'rest-client'
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
      return HTTParty.post(create_uri('/api/v1/statuses'), {
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

    def upload(path)
      response = RestClient.post(
        create_uri('/api/v1/media').to_s,
        {file: File.new(path, 'rb')},
        {
          'User-Agent' => Package.user_agent,
          'Authorization' => "Bearer #{@token}",
        },
      )
      return JSON.parse(response.body)['id'].to_i
    end

    private

    def create_uri(href)
      uri = Addressable::URI.parse(@params['url'])
      uri.path = href
      return uri
    end
  end
end
