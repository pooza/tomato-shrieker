module TomatoShrieker
  class Scheduler
    include Singleton
    include Package

    def exec
      Source.all.reject(&:disable?).each do |source|
        source.register
      end
      @scheduler.join
    rescue => e
      logger.error(scheduler: {error: e})
    end

    private

    def initialize
      @scheduler = Rufus::Scheduler.new
      @scheduler.cron('@hourly', 'purge') do
        FeedSource.purge_all
      end
    end
  end
end
