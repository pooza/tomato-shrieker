module TomatoShrieker
  class LineShrieker
    def initialize(user_id, token)
      @http = HTTP.new
      @http.base_uri = 'https://api.line.me'
      @logger = Logger.new
      @user_id = user_id
      @token = token
    end

    def exec(body)
      @logger.info(body)
      return @http.post('/v2/bot/message/push', {
        headers: {'Authorization' => "Bearer #{@token}"},
        body: {
          to: @user_id,
          messages: [{type: 'text', text: body[:text]}],
        }.to_json
      })
    end
  end
end
