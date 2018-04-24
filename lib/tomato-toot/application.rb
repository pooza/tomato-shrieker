require 'optparse'
require 'active_support'
require 'active_support/core_ext'
require 'tomato-toot/package'
require 'tomato-toot/feed'
require 'tomato-toot/slack'
require 'tomato-toot/config'
require 'tomato-toot/logger'

module TomatoToot
  class Application
    def initialize
      @config = Config.instance
      @logger = Logger.new(Package.name)
      @slack = Slack.new if @config['local']['slack']
      @options = ARGV.getopts('', 'silence')
    rescue => e
      puts "#{e.class} #{e.message}"
      exit 1
    end

    def execute
      @logger.info({message: 'start', version: Package.version})
      @config['local']['entries'].each do |entry|
        begin
          feed = Feed.new(entry)
          raise 'empty' unless feed.present?
          @logger.info(feed.params)
          if feed.touched?
            feed.fetch do |entry|
              feed.toot(entry) unless @options['silence']
              @logger.info({toot: entry[:body], options: @options})
            end
          else
            entry = feed.fetch.to_a.last
            feed.toot(entry) unless @options['silence']
            @logger.info({toot: entry[:body], options: @options})
          end
          feed.touch
        rescue => e
          message = entry.clone
          message['error'] = e.message
          @slack.say(message) if @slack
          @logger.error(message)
        end
      end
      @logger.info({message: 'complete', version: Package.version})
    end
  end
end
