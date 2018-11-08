require 'json'

module TomatoToot
  class JsonRenderer < Renderer
    attr_accessor :message

    def to_s
      return @message.to_json
    end
  end
end
