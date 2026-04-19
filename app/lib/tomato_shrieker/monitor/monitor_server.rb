require 'puma/server'

module TomatoShrieker
  class MonitorServer
    include Package

    def enabled?
      return Config.instance['/monitor/enabled']
    end

    def start
      return unless enabled?
      @server = Puma::Server.new(MonitorApp.new)
      @server.add_tcp_listener(bind, port)
      @server.run
      logger.info(daemon: 'monitor', message: 'start', bind:, port:)
    rescue => e
      Sentry.capture_exception(e) if Sentry.initialized?
      logger.error(daemon: 'monitor', error: e)
    end

    def stop
      return unless @server
      logger.info(daemon: 'monitor', message: 'stop')
      @server.stop(true)
    end

    private

    def bind
      return Config.instance['/monitor/bind']
    end

    def port
      return Config.instance['/monitor/port']
    end
  end
end
