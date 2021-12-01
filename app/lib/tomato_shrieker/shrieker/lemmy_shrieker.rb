require 'eventmachine'
require 'faye/websocket'

module TomatoShrieker
  class LemmyShrieker
    include Package

    def initialize(params = {})
      @params = params.deep_symbolize_keys
    end

    def client
      @client ||= Faye::WebSocket::Client.new(uri.to_s, [], {
        tls: {
          verify_peer: verify_peer?,
        },
        ping: keepalive,
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

    def keepalive
      return config['/websocket/keepalive']
    end

    def verify_peer?
      return config['/lemmy/verify_peer']
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

        client.on(:error) do |e|
          raise e.message
        end

        client.on(:message) do |message|
          payload = JSON.parse(message.data)
          raise payload['error'] if payload['error']
          method = "handle_#{payload['op']}".underscore.to_sym
          EM.stop_event_loop if send(method, payload['data'], body) == :stop
        end
      rescue => e
        logger.error(error: e)
        EM.stop_event_loop
      end
    end

    private

    def login
      client.send({op: 'Login', data: {
        username_or_email: @params[:user_id],
        password: (@params[:password].decrypt rescue @params[:password]),
      }}.to_json)
    end

    def post(body)
      template = body[:template]
      uri = (template.entry || template.source).uri rescue nil
      uri ||= Ginseng::URI.scan(template.to_s).first
      client.send({op: 'CreatePost', data: {
        nsfw: false,
        name: template.to_s.gsub(/\s+/, ' ').ellipsize(config['/lemmy/subject/max_length']),
        url: uri.to_s,
        community_id: template.source['/dest/lemmy/community_id'],
        auth: @jwt,
      }}.to_json)
    end
  end
end
