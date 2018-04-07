require 'json'
require 'bitly'
require 'tomato-toot/config'

module TomatoToot
  class Bitly
    def initialize
      ::Bitly.use_api_version_3
      ::Bitly.configure do |config|
        config.api_version = 3
        config.access_token = Config.instance['local']['bitly']['token']
      end
      @service = ::Bitly.client
    end

    def shorten (url)
      return @service.shorten(url).short_url
    end
  end
end
