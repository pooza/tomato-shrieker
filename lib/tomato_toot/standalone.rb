require 'optparse'

module TomatoToot
  class Standalone
    def initialize
      @logger = Logger.new
      @options = ARGV.getopts('', 'silence')
    rescue => e
      puts "#{e.class} #{e.message}"
      exit 1
    end

    def execute
      Feed.all do |feed|
        @logger.info(feed.params)
        feed.execute(@options)
      rescue => e
        e = Ginseng::Error.create(e)
        Slack.broadcast(e.to_h)
        @logger.error(e.to_h)
        next
      end
    end
  end
end
