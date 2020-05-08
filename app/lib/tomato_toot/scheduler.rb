require 'rufus-scheduler'

module TomatoToot
  class Scheduler
    include Singleton

    def exec
      Feed.all do |feed|
        @logger.info(feed: feed.hash, period: feed.period, message: 'start scheduler')
        @scheduler.every(feed.period) do
          Sequel.connect(Environment.dsn).transaction do
            feed.exec
          end
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
