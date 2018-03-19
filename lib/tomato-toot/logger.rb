require 'json'
require 'syslog/logger'

module TomatoToot
  class Logger
    def initialize (name)
      @logger = Syslog::Logger.new(name)
    end

    def info (message)
      @logger.info(message.to_json)
    end

    def warning (message)
      @logger.warn(message.to_json)
    end

    def error (message)
      @logger.error(message.to_json)
    end

    def fatal (message)
      @logger.fatal(message.to_json)
    end
  end
end
