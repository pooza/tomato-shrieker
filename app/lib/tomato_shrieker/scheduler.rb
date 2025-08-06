module TomatoShrieker
  class Scheduler
    include Singleton
    include Package

    def exec
      logger.info(scheduler: {message: 'initialize'})
      Source.all.reject(&:disable?).each do |source|
        source.load
        job = register(source)
        if source.post_at
          logger.info(source: source.id, job:, class: source.class.to_s, at: source.post_at)
        elsif source.cron
          logger.info(source: source.id, job:, class: source.class.to_s, cron: source.cron)
        else
          logger.info(source: source.id, job:, class: source.class.to_s,
            every: source.every)
        end
      end
      logger.info(scheduler: {message: 'initialized'})
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

    def register(source)
      job = @scheduler.at(source.post_at, {tag: source.id}) do
        logger.info(source: source.id, class: source.class.to_s, action: 'exec start')
        source.exec
        logger.info(source: source.id, class: source.class.to_s, action: 'exec end')
      rescue => e
        logger.error(source: source.id, error: e)
      end
      return job
    end
  end
end
