require 'addressable/uri'
require 'httparty'
require 'json'

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
          'Authorization' => "Bearer #{@params['token']}",
        },
        ssl_ca_file: File.join(ROOT_DIR, 'cert/cacert.pem'),
      })
    end
  end
end
