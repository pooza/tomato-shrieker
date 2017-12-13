require 'active_support'
require 'active_support/core_ext'
require 'json'
require 'mastodon'
require 'syslog/logger'
require 'tomato-toot/feed'
require 'tomato-toot/config'

module TomatoToot
  class Application
    def initialize
      @config = Config.new
      @logger = Syslog::Logger.new(@config['application']['name'])
    end

    def execute
      @logger.info({message: 'start', version: @config['application']['version']}.to_json)
      @config['local']['entries'].each do |entry|
        feed = Feed.new(entry)
        if feed.touched?
          mastodon = Mastodon::REST::Client.new({
            base_url: entry['mastodon']['url'],
            bearer_token: entry['mastodon']['token'],
          })
          @logger.info(feed.params.to_json)
          feed.fetch do |body|
            mastodon.create_status(body)
            @logger.info({toot: body}.to_json)
          end
        end
        feed.touch
      end
      @logger.info({message: 'complete', version: @config['application']['version']}.to_json)
    rescue => e
      puts "#{e.class} #{e.message}"
      @logger.error({class: e.class, message: e.message}.to_json)
      @logger.info({message: 'failed', version: @config['application']['version']}.to_json)
      exit 1
    end
  end
end
