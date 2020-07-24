require 'rufus-scheduler'

module TomatoToot
  class Scheduler
    include Singleton

    def exec
      Sequel.connect(Environment.dsn)
      Source.all do |source|
        @logger.info(source: source.hash, period: source.period, message: 'start scheduler')
        if source.post_at
          @scheduler.at(source.post_at, {tag: source.hash}) {source.exec}
        elsif source.cron
          @scheduler.cron(source.cron, {tag: source.hash}) {source.exec}
        else
          @scheduler.every(source.period, {tag: source.hash}) {source.exec}
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
