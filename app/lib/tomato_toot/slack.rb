module TomatoToot
  class Slack < Ginseng::Slack
    include Package

    def say(message, type = :yaml)
      r = super(message, type)
      raise Ginseng::GatewayError, "response #{r.code} (#{uri})" unless r.code == 200
      return r
    end

    def self.all
      return enum_for(__method__) unless block_given?
      Config.instance['/slack/hooks'].each do |url|
        yield Slack.new(url)
      end
    end
  end
end
