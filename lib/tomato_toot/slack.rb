require 'addressable/uri'
require 'httparty'
require 'json'

module TomatoToot
  class Slack
    def initialize(uri)
      @uri = Addressable::URI.parse(uri)
    end

    def say(message)
      return HTTParty.post(@uri, {
        body: {text: JSON.pretty_generate(message)}.to_json,
        headers: {
          'Content-Type' => 'application/json',
          'User-Agent' => Package.user_agent,
        },
        ssl_ca_file: ENV['SSL_CERT_FILE'],
      })
    end

    def self.all
      return enum_for(__method__) unless block_given?
      Config.instance['/slack/hooks'].each do |uri|
        yield Slack.new(uri)
      end
    end

    def self.broadcast(message)
      all do |slack|
        slack.say(message)
      end
    end
  end
end
