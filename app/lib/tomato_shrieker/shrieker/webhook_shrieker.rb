module TomatoShrieker
  class WebhookShrieker < SlackService
    include Package

    def initialize(hook)
      case hook
      when Ginseng::URI
        super
      when String
        super(Ginseng::URI.parse(hook))
      when Hash
        super(hook[:url])
        @params = hook
      end
    end

    def exec(body)
      return post(body)
    end

    def channel
      return @params[:channel] rescue nil # matrix-webhook で使用
    end

    def room_id
      return @params[:room_id] rescue nil # matrix-webhook で使用
    end

    def post(body, type = :hash)
      return @http.post(@uri, {body: create_body(body)})
    end

    def create_body(body, type = :hash)
      body = body.clone
      body[:template][:tag] = true
      body[:text] = body[:template].to_s.strip
      if spoiler_text = body[:template].source.spoiler_text
        body[:spoiler_text] = spoiler_text
      end
      body[:channel] ||= channel if channel
      body[:room_id] ||= room_id if room_id
      body.delete(:template)
      return body.to_json
    end
  end
end
