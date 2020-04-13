module TomatoToot
  class Slack < Ginseng::Slack
    include Package
    attr_reader :url

    alias uri url

    def self.all
      return enum_for(__method__) unless block_given?
      Config.instance['/slack/hooks'].each do |url|
        yield Slack.new(url)
      end
    end
  end
end
