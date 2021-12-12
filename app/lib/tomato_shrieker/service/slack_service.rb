module TomatoShrieker
  class SlackService < Ginseng::Slack
    include Package

    def self.all(&block)
      return enum_for(__method__) unless block
      config['/slack/hooks'].map {|v| SlackService.new(v)}.each(&block)
    end
  end
end
