require 'rufus-scheduler'

module TomatoToot
  class Scheduler
    include Singleton

    def exec
      Source.all do |source|
        @logger.info(source: source.hash, period: source.period, message: 'start scheduler')
        Sequel.connect(Environment.dsn)
        @scheduler.every(source.period) do
          source.exec
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
