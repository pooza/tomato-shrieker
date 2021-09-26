module TomatoShrieker
  class SlackService < Ginseng::Slack
    include Package

    def self.all
      return enum_for(__method__) unless block_given?
      config['/slack/hooks'].each do |url|
        yield SlackService.new(url)
      end
    end
  end
end
