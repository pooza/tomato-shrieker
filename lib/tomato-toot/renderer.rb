require 'tomato-toot/config'
require 'tomato-toot/logger'
require 'tomato-toot/error/imprement'

module TomatoToot
  class Renderer
    attr_accessor :status

    def initialize
      @status = 200
      @config = Config.instance
      @logger = Logger.new
    end

    def type
      return 'application/json; charset=UTF-8'
    end

    def to_s
      raise ImprementError, "#{__method__}が未定義です。"
    end
  end
end
