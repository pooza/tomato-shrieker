module TomatoShrieker
  class Scheduler
    include Singleton
    include Package

    attr_reader :scheduler

    def exec
      Source.all.reject(&:disable?).each(&:register)
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
