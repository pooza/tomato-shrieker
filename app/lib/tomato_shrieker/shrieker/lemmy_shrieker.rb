require 'eventmachine'
require 'faye/websocket'

module TomatoShrieker
  class LemmyShrieker
    include Package

    def initialize(params = {})
      @params = params.deep_symbolize_keys
    end

    def client
      @client ||= Faye::WebSocket::Client.new(uri.to_s, nil, {
        ping: config['/websocket/keepalive'],
      })
      return @client
    end

    def uri
      unless @uri
        @uri = Ginseng::URI.parse("wss://#{@params[:host]}")
        @uri.path = config['/lemmy/urls/api']
      end
      return @uri
    end

    def handle_login(payload, body)
      @jwt = payload['jwt']
      post(body)
    end

    def handle_create_post(payload, body)
      return :stop
    end

    def exec(body)
      EM.run do
        login

        client.on(:close) do |e|
          EM.stop_event_loop
        end

        client.on(:error) do |e|
          logger.error(error: e.message)
          EM.stop_event_loop
        end

        client.on(:message) do |message|
          payload = JSON.parse(message.data)
          raise payload['error'] if payload['error']
          method = "handle_#{payload['op']}".underscore.to_sym
          EM.stop_event_loop if send(method, payload['data'], body) == :stop
        rescue => e
          logger.error(error: e)
          EM.stop_event_loop
        end
      end
    end

    private

    def login
      client.send({op: 'Login', data: {
        username_or_email: @params[:user_id],
        password: @params[:password].decrypt,
      }}.to_json)
    end

    def post(body)
      template = body[:template]
      title = template.entry.title || template[:status]
      title = "[#{template.source.prefix}] #{title}" unless template.source.bot?
      client.send({op: 'CreatePost', data: {
        nsfw: false,
        name: title,
        url: template.entry.uri.to_s,
        community_id: template.source['/dest/lemmy/community_id'],
        auth: @jwt,
      }}.to_json)
    end
  end
end
