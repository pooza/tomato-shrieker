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
          root_cert_file:,
          logger:,
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

    def root_cert_file
      return config['/lemmy/root_cert_file']
    rescue
      return ENV['SSL_CERT_FILE']
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
          raise 'Empty message (rate limit?)' unless payload
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
      client.send(op: 'Login', data: {
        username_or_email: @params[:user_id],
        password: (@params[:password].decrypt rescue @params[:password]),
      })
    end

    def post(body)
      template = search_template(body)
      data = {
        name: template.to_s.gsub(/[\s[:blank:]]+/, ' '),
        body: template.to_s,
        community_id: template.source['/dest/lemmy/community_id'],
        auth: @jwt,
      }
      Ginseng::URI.scan(data[:body]).each {|uri| data[:name].gsub!(uri.to_s, '')}
      data[:name].ellipsize!(config['/lemmy/subject/max_length'])
      uri = (template.entry || template.source).uri rescue Ginseng::URI.scan(template.to_s).first
      data[:url] = uri.to_s if uri
      client.send(op: 'CreatePost', data:)
    end

    def search_template(body)
      unless entry = body[:template].entry
        return body[:template].source.create_template(:lemmy, body[:template].to_s)
      end
      return entry.create_template(:lemmy)
    rescue
      return body[:template]
    end
  end
end
