require 'json'
require 'syslog/logger'
require 'tomato-toot/package'

module TomatoToot
  class Logger
    def initialize
      @logger = Syslog::Logger.new(Package.name)
    end

    def info (message)
      message['package'] = {name: Package.name, version: Package.version}
      @logger.info(message.to_json)
    end

    def warning (message)
      message['package'] = {name: Package.name, version: Package.version}
      @logger.warn(message.to_json)
    end

    def error (message)
      message['package'] = {name: Package.name, version: Package.version}
      @logger.error(message.to_json)
    end

    def fatal (message)
      message['package'] = {name: Package.name, version: Package.version}
      @logger.fatal(message.to_json)
    end
  end
end
