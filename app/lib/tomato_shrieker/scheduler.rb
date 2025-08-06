module TomatoShrieker
  class Scheduler
    include Singleton
    include Package

    def exec
      logger.info(scheduler: {message: 'initialize'})
      Source.all.reject(&:disable?).each do |source|
        source.load
        if source.post_at
          job = @scheduler.at(source.post_at, {tag: source.id}) do
            logger.info(source: source.id, class: source.class.to_s, action: 'exec start',
              at: source.post_at)
            source.exec
            logger.info(source: source.id, class: source.class.to_s, action: 'exec end')
          rescue => e
            logger.error(source: source.id, error: e)
          end
          logger.info(source: source.id, job:, class: source.class.to_s, at: source.post_at)
        elsif source.cron
          job = @scheduler.cron(source.cron, {tag: source.id}) do
            logger.info(source: source.id, class: source.class.to_s, action: 'exec start',
              cron: source.cron)
            source.exec
            logger.info(source: source.id, class: source.class.to_s, action: 'exec end')
          rescue => e
            logger.error(source: source.id, error: e)
          end
          logger.info(source: source.id, job:, class: source.class.to_s, cron: source.cron)
        else
          job = @scheduler.every(source.period, {tag: source.id}) do
            logger.info(source: source.id, class: source.class.to_s, action: 'exec start',
              every: source.every)
            source.exec
            logger.info(source: source.id, class: source.class.to_s, action: 'exec end')
          rescue => e
            logger.error(source: source.id, error: e)
          end
          logger.info(source: source.id, job:, class: source.class.to_s, every: source.every)
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
  end
end
