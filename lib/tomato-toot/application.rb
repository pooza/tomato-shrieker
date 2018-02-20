require 'active_support'
require 'active_support/core_ext'
require 'json'
require 'syslog/logger'
require 'tomato-toot/feed'
require 'tomato-toot/slack'
require 'tomato-toot/config'

module TomatoToot
  class Application
    def initialize
      @config = Config.instance
      @slack = Slack.new if @config['local']['slack']
    end

    def execute
      Application.logger.info({message: 'start', version: Application.version}.to_json)
      @config['local']['entries'].each do |entry|
        begin
          feed = Feed.new(entry)
          Application.logger.info(feed.params.to_json)
          if feed.touched?
            feed.fetch do |body|
              feed.mastodon.create_status(body)
              Application.logger.info({toot: body}.to_json)
            end
          else
            body = feed.fetch.to_a.last
            feed.mastodon.create_status(body)
            Applicaiton.logger.info({toot: body}.to_json)
          end
          feed.touch
        rescue => e
          message = entry.clone
          message['error'] = e.message
          @slack.say(message) if @slack
          Application.logger.error({class: e.class, message: e.message}.to_json)
        end
      end
      Application.logger.info({message: 'complete', version: Application.version}.to_json)
    end

    def self.name
      return Config.instance['application']['name']
    end

    def self.version
      return Config.instance['application']['version']
    end

    def self.url
      return Config.instance['application']['url']
    end

    def self.full_name
      return "#{Application.name} #{Application.version}"
    end

    def self.logger
      return Syslog::Logger.new(Application.name)
    end
  end
end
