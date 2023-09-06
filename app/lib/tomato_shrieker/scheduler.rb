module TomatoShrieker
  class Scheduler
    include Singleton
    include Package

    def exec
      logger.info(scheduler: {message: 'initialize'})
      Source.all.reject(&:disable?).each do |source|
        logger.info(source: source.to_h)
        source.load
        if source.post_at
          @scheduler.at(source.post_at, {tag: source.id}) {source.exec}
        elsif source.cron
          @scheduler.cron(source.cron, {tag: source.id}) {source.exec}
        else
          @scheduler.every(source.period, {tag: source.id}) {source.exec}
        end
      end
      logger.info(scheduler: {message: 'initialized'})
      @scheduler.join
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
