module TomatoShrieker
  class Scheduler
    include Singleton
    include Package

    attr_reader :scheduler

    def exec
      in_threads = Parallel.processor_count * 2
      Parallel.each(Source.all.reject(&:disable?), in_threads:, &:register)
      @scheduler.join
    rescue => e
      logger.error(scheduler: {error: e})
    end

    private

    def initialize
      @scheduler = Rufus::Scheduler.new
    end
  end
end
