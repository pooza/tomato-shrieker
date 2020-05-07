require 'rufus-scheduler'

module TomatoToot
  class Scheduler
    include Singleton

    def exec
      @scheduler.every '3s' do
        @logger.info('Hello')
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
