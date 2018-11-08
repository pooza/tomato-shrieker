require 'addressable/uri'
require 'digest/sha1'
require 'json'
require 'socket'

module TomatoToot
  class Webhook
    attr_reader :mastodon

    def initialize(params)
      @config = Config.instance
      @params = params.clone
      @logger = Logger.new
      @mastodon = Mastodon.new(@params['mastodon'])
    end

    def digest
      return Digest::SHA1.hexdigest({
        mastodon: mastodon_url,
        token: token,
        visibility: visibility,
        shorten: shorten?,
        salt: (@config['local']['salt'] || @config['local']),
      }.to_json)
    end

    def mastodon_url
      return @params['mastodon']['url']
    end

    def token
      return @params['mastodon']['token']
    end

    def visibility
      return (@params['visibility'] || 'public')
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

    def shorten?
      return @config['local']['bitly'] && @params['shorten']
    end

    def to_json
      return JSON.pretty_generate({
        mastodon: mastodon_url,
        token: token,
        visibility: visibility,
        shorten: shorten?,
        hook: hook_url,
      })
    end

    def toot(body)
      @mastodon.toot(body, {
        visibility: visibility,
      })
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
