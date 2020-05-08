require 'rufus-scheduler'

module TomatoToot
  class Scheduler
    include Singleton

    def exec
      Feed.all do |feed|
        @logger.info(feed: feed.hash, period: feed.period, message: 'start scheduler')
        Sequel.connect(Environment.dsn)
        @scheduler.every(feed.period) do
          feed.exec
        end
      end
      @scheduler.join
    end

    private

    def initialize
      @scheduler = Rufus::Scheduler.new
      @logger = Logger.new
    end
  end
end
