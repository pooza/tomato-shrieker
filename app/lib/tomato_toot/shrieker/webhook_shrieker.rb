module TomatoToot
  class WebhookShrieker < Ginseng::Slack
    include Package

    def exec(body)
      body.delete(:visibility)
      return say(body, :hash)
    end
  end
end
