require 'eventmachine'
require 'faye/websocket'

module TomatoShrieker
  class LemmyShrieker
    include Package

    def initialize(params = {})
      @params = params
    end

    def client
      @client ||= Faye::WebSocket::Client.new(uri.to_s, nil, {
        ping: config['/websocket/keepalive'],
      })
      return @client
    end

    def uri
      unless @uri
        @uri = Ginseng::URI.parse("wss://#{@params['host']}")
        @uri.path = config['/lemmy/urls/api']
      end
      return @uri
    end

    def login
      client.send({op: 'Login', data: {
        username_or_email: @params['user_id'],
        password: @params['password'].decrypt,
      }}.to_json)
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
          raise Ginseng::GatewayError, e.message
        end

        client.on(:message) do |message|
          payload = JSON.parse(message.data)
          raise payload['error'] if payload['error']
          @response = send("handle_#{payload['op']}".underscore.to_sym, payload['data'], body)
        rescue => e
          logger.error(error: e)
          EM.stop_event_loop
        end
      end
      return @response
    end

    def handle_login(payload, body)
      @auth = payload['jwt']
      params = body[:template].params.deep_symbolize_keys
      source = params[:source] || params[:feed]
      return client.send({op: 'CreatePost', data: {
        name: (params[:entry]&.title || params[:status]),
        url: params[:entry]&.uri&.to_s,
        nsfw: false,
        community_id: source['/dest/lemmy/community_id'],
        auth: @auth,
      }}.to_json)
    end
  end
end
