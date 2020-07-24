require 'rufus-scheduler'

module TomatoShrieker
  class Scheduler
    include Singleton

    def exec
      Sequel.connect(Environment.dsn)
      @logger.info(scheduler: {message: 'start'})
      Source.all do |source|
        @logger.info(source: source.to_h)
        if source.post_at
          @scheduler.at(source.post_at, {tag: source.hash}) {source.exec}
        elsif source.cron
          @scheduler.cron(source.cron, {tag: source.hash}) {source.exec}
        else
          @scheduler.every(source.period, {tag: source.hash}) {source.exec}
        end
      end
      @logger.info(scheduler: {message: 'initialized'})
      @scheduler.join
    end

    private

    def initialize
      @scheduler = Rufus::Scheduler.new
      @logger = Logger.new
    end
  end
end
