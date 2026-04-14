module TomatoShrieker
  class Scheduler
    include Singleton
    include Package

    attr_reader :scheduler

    def exec
      in_threads = Parallel.processor_count * 2
      Parallel.each(Source.all.reject(&:disable?), in_threads:, &:register)
      schedule_maintenance
      @scheduler.join
    rescue => e
      Sentry.capture_exception(e) if Sentry.initialized?
      logger.error(scheduler: {error: e})
    end

    private

    def initialize
      @scheduler = Rufus::Scheduler.new
    end

    def schedule_maintenance
      retention = Config.instance['/monitor/retention_days']
      @scheduler.every '1d', first_in: '1m' do
        count = SourceRunLog.prune(retention)
        logger.info(scheduler: 'maintenance', action: 'prune', retention_days: retention,
          deleted: count)
      rescue => e
        Sentry.capture_exception(e) if Sentry.initialized?
        logger.error(scheduler: 'maintenance', error: e)
      end
    end
  end
end
