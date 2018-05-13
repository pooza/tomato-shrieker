require 'json'
require 'tomato-toot/renderer'

module TomatoToot
  class JSON < Renderer
    attr_accessor :message

    def to_s
      return @message.to_json
    end
  end
end
