module TomatoShrieker
  class WebhookShrieker < SlackService
    include Package

    def exec(body)
      body = body.clone
      body[:template][:tag] = true
      body[:text] = body[:template].to_s.strip
      if spoiler_text = body[:template].source.spoiler_text
        body[:spoiler_text] = spoiler_text
      end
      body.delete(:template)
      return say(body, :hash)
    end
  end
end
