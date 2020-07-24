module TomatoToot
  class WebhookShrieker < Ginseng::Slack
    include Package

    def exec(body)
      return say(body, :hash)
    end
  end
end
