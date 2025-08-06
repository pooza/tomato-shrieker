module TomatoShrieker
  class Scheduler
    include Singleton
    include Package

    def exec
      Source.all.reject(&:disable?).each do |source|
        source.load
        if source.post_at
          register_at(source)
        elsif source.cron
          register_cron(source)
        else
          register_every(source)
        end
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

    def register_at(source)
      schedule(source, :at, source.post_at, at: source.post_at)
    end

    def register_cron(source)
      schedule(source, :cron, source.cron, cron: source.cron)
    end

    def register_every(source)
      schedule(source, :every, source.period, every: source.every)
    end

    def schedule(source, method, time_spec, log_info)
      job = @scheduler.send(method, time_spec, {tag: source.id}) do
        logger.info(source: source.id, class: source.class.to_s, action: 'exec start', **log_info)
        source.exec
        logger.info(source: source.id, class: source.class.to_s, action: 'exec end')
      rescue => e
        logger.error(source: source.id, error: e)
      end
      logger.info(source: source.id, job:, class: source.class.to_s, **log_info)
    end
  end
end
