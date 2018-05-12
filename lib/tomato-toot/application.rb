require 'optparse'
require 'active_support'
require 'active_support/core_ext'
require 'tomato-toot/feed'
require 'tomato-toot/slack'
require 'tomato-toot/config'
require 'tomato-toot/logger'

module TomatoToot
  class Application
    def initialize
      @config = Config.instance
      @logger = Logger.new
      @slack = Slack.new if @config['local']['slack']
      @options = ARGV.getopts('', 'silence')
    rescue => e
      puts "#{e.class} #{e.message}"
      exit 1
    end

    def execute
      @logger.info({message: 'start'})
      @config['local']['entries'].each do |entry|
        begin
          Feed.new(entry).execute(@options)
          @logger.info(entry)
        rescue => e
          message = entry.clone
          message['error'] = e.message
          @slack.say(message) if @slack
          @logger.error(message)
        end
      end
      @logger.info({message: 'complete'})
    end
  end
end
