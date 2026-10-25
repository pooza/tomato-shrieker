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

    # 🔴 **リレーが受理した（NIP-20 の `OK` が true で返った）ときだけ配信できたとみなす (#1479)。**
    # どのリレーも受理しなければ例外にする。黙って正常終了すると Source#shriek が配信成功として
    # 計上し、サイレント不発の検知（#1470）の根拠が水増しされる。
    # ⚠ 以前は `on :connect` で送るだけで、`publish` が例外なく戻っても受理の証明にならなかった。
    # ⚠ 1 つでも受理されれば成功（どこかへは届いている）。受理しなかったリレーはログに残す。
    def publish(event)
      threads = relays.map {|relay_url| Thread.new {publish_to(relay_url, event)}}
      accepted = threads.map(&:value).count(true)
      return if accepted.positive?
      raise Ginseng::GatewayError, "no nostr relay accepted the event (#{relays.count} relay(s))"
    end

    # 1 リレーぶん。受理されたら true。⚠ 待つのは `publish_timeout` 秒まで（返らないリレーは失敗）。
    # ⚠ ハンドラは `connect` の前に張る（接続が先に開くと `:connect` を取りこぼす）。
    # 🔴 **ハンドラの中では self がクライアントになる**（EventEmitter が `instance_exec` する）。
    # このクラスのメソッドは外で `method` に取ってから使う。
    def publish_to(relay_url, event)
      results = Thread::Queue.new
      parse = method(:relay_ok)
      client = create_client
      client.on(:connect) {|_relay| client.publish(event)}
      client.on(:message) do |data|
        result = parse.call(data, event.id)
        results.push(result) if result
      end
      client.on(:error) {|message| results.push([false, "error: #{message}"])}
      client.on(:close) {|code, reason| results.push([false, "closed: #{code} #{reason}"])}
      client.connect(Nostr::Relay.new(url: relay_url, name: relay_url))
      accepted, message = results.pop(timeout: publish_timeout) || [false, 'timeout']
      logger.error(nostr: {relay: relay_url, message:}) unless accepted
      return accepted
    rescue => e
      logger.error(nostr: {relay: relay_url, error: e})
      return false
    end

    def create_client
      return Nostr::Client.new
    end

    # `["OK", <event id>, <accepted>, <message>]`（NIP-20）なら [受理したか, 理由]。ほかは nil。
    def relay_ok(data, event_id)
      message = JSON.parse(data.to_s)
      return nil unless message.is_a?(Array) && message[0] == 'OK' && message[1] == event_id
      return [message[2] == true, message[3]]
    rescue JSON::ParserError
      return nil
    end

    def publish_timeout
      return config['/nostr/publish/timeout/seconds']
    end
  end
end
