module TomatoShrieker
  class NostrShrieker
    include Package

    def initialize(params = {})
      @params = params.deep_symbolize_keys
      @keypair = create_keypair
    end

    def exec(body)
      body = body.clone
      body[:template][:tag] = true
      event = user.create_event(
        kind: Nostr::EventKind::TEXT_NOTE,
        content: body[:template].to_s.strip,
      )
      publish(event)
    end

    def relays
      @params[:relays] || config['/nostr/relays']
    end

    private

    def create_keypair
      keygen = Nostr::Keygen.new
      private_key = @params[:private_key].decrypt rescue @params[:private_key]
      keygen.get_key_pair_from_private_key(Nostr::PrivateKey.new(private_key))
    end

    def user
      @user ||= Nostr::User.new(keypair: @keypair)
    end

    def publish(event)
      relays.each do |relay_url|
        client = Nostr::Client.new
        relay = Nostr::Relay.new(url: relay_url, name: relay_url)
        client.connect(relay)
        client.on :connect do
          client.publish(event)
        end
      rescue => e
        logger.error(nostr: {relay: relay_url, error: e})
      end
    end
  end
end
