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
      key = if private_key.start_with?('nsec1')
        Nostr::PrivateKey.from_bech32(private_key)
      else
        Nostr::PrivateKey.new(private_key)
      end
      keygen.get_key_pair_from_private_key(key)
    end

    def user
      @user ||= Nostr::User.new(keypair: @keypair)
    end

    # 全リレーに繋がらなかった場合は例外にする。黙って正常終了すると
    # Source#shriek が配信成功として計上し、サイレント不発の検知が効かなくなる (#1470)。
    # ⚠ publish 自体は on :connect のコールバックで非同期に走るため、例外が出ない
    # ことは配信できたことの証明にはならない。リレーの OK を待つ話は #1473。
    def publish(event)
      failed = relays.count do |relay_url|
        client = Nostr::Client.new
        relay = Nostr::Relay.new(url: relay_url, name: relay_url)
        client.connect(relay)
        client.on :connect do
          client.publish(event)
        end
        next false
      rescue => e
        logger.error(nostr: {relay: relay_url, error: e})
        next true
      end
      return if failed < relays.count
      raise Ginseng::GatewayError, "all #{relays.count} nostr relay(s) failed"
    end
  end
end
