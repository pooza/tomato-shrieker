require 'optparse'

module TomatoToot
  class Standalone
    def initialize
      @config = Config.instance
      @logger = Logger.new
      @options = ARGV.getopts('', 'silence')
    rescue => e
      puts "#{e.class} #{e.message}"
      exit 1
    end

    def execute
      @logger.info({mode: 'standalone', message: 'start'})
      Feed.all do |feed|
        @logger.info({mode: 'standalone', feed: feed.params})
        feed.execute(@options)
      rescue => e
        e = Error.create(e)
        Slack.broadcast(e.to_h)
        @logger.error(e.to_h)
        next
      end
    ensure
      @logger.info({mode: 'standalone', message: 'complete'})
    end
  end
end
