module TomatoShrieker
  class Scheduler
    include Singleton
    include Package

    attr_reader :scheduler

    def exec
      sources = Source.all.reject(&:disable?)
      Parallel.each(sources, in_threads: Environment.parallel_thread_count, &:register)
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
