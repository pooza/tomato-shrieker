module TomatoShrieker
  class WebhookShrieker < Ginseng::Slack
    include Package

    def exec(body)
      body = body.clone
      body[:template][:tag] = true
      body[:text] = body[:template].to_s.strip
      body.delete(:template)
      body.delete(:visibility)
      return say(body, :hash)
    end
  end
end
