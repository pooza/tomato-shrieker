require 'addressable/uri'
require 'digest/sha1'
require 'mastodon'
require 'json'
require 'socket'
require 'tomato-toot/config'
require 'tomato-toot/logger'

module TomatoToot
  class Webhook
    def initialize(params)
      @config = Config.instance
      @params = params.clone
      @logger = Logger.new
      @mastodon = Mastodon::REST::Client.new({
        base_url: @params['mastodon']['url'],
        bearer_token: @params['mastodon']['token'],
      })
    end

    def digest
      values = @params.clone
      values['salt'] = (@config['local']['salt'] || @config['local'])
      return Digest::SHA1.hexdigest(@values.to_s)
    end

    def mastodon_url
      return @params['mastodon']['url']
    end

    def token
      return @params['mastodon']['token']
    end

    def hook_url
      unless url = Addressable::URI.parse(@config['local']['root_url'])
        url = Addressable::URI.new
        url.host = Socket.gethostname
        url.port = @config['thin']['port']
        url.scheme = 'http'
      end
      url.path = "/webhook/v1.0/toot/#{digest}"
      return url.to_s
    end

    def to_json
      return ::JSON.pretty_generate({
        mastodon: mastodon_url,
        token: token,
        hook: hook_url,
      })
    end

    def toot(body)
      @mastodon.create_status(body)
    end

    def self.search(digest)
      all do |webhook|
        return webhook if digest == webhook.digest
      end
      return nil
    end

    def self.all
      return enum_for(__method__) unless block_given?
      Config.instance['local']['entries'].each do |entry|
        next unless entry['webhook']
        yield Webhook.new(entry)
      end
    end
  end
end
