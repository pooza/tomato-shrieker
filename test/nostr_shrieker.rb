module TomatoShrieker
  class NostrShriekerTest < TestCase
    def disable?
      return true if Source.all.none? {|s| s.test? && s.nostr?}
      return super
    end

    def test_exec
      Source.all.select(&:test?).select(&:nostr?).each do |source|
        source.clear
        assert_nothing_raised {source.exec}
      end
    end

    def test_templates
      Source.all.select(&:test?).select(&:nostr?).each do |source|
        assert_kind_of(Hash, source.templates)
        assert_kind_of(Template, source.templates[:default])
      end
    end
  end
end

module TomatoShrieker
  # 🔴 #1479: リレーの `OK`（NIP-20）を待つ。⚠ 上の NostrShriekerTest は宛先を持つテスト用ソースが
  # 無いと丸ごと省かれる（Nostr は秘密鍵を置かない方針）ので、偽のクライアントで閉じて確かめる。
  class NostrShriekerOfflineTest < TestCase
    RELAYS = ['wss://relay1.example.test', 'wss://relay2.example.test'].freeze

    # `connect` で `:connect` を出し、`publish` で決めた応答を返すだけのクライアント。
    class FakeClient
      include EventEmitter

      def initialize(reply)
        @reply = reply
      end

      def connect(_relay)
        Thread.new {emit(:connect, nil)}
      end

      def publish(event)
        @reply&.call(self, event)
      end
    end

    ACCEPT = proc {|client, event| client.emit(:message, ['OK', event.id, true, ''].to_json)}
    REJECT = proc {|client, event| client.emit(:message, ['OK', event.id, false, 'blocked: spam'].to_json)}
    OTHER_EVENT = proc {|client, _event| client.emit(:message, ['OK', 'f' * 64, true, ''].to_json)}
    CLOSE = proc {|client, _event| client.emit(:close, 1006, 'gone')}

    def test_accepted
      assert_nothing_raised {publish_with(ACCEPT, ACCEPT)}
    end

    # ⚠ 1 つでも受理されれば成功（どこかへは届いている）。
    def test_partially_accepted
      assert_nothing_raised {publish_with(ACCEPT, REJECT)}
    end

    def test_rejected
      assert_raise(Ginseng::GatewayError) {publish_with(REJECT, REJECT)}
    end

    # 🔴 送っただけで返事が無いリレーは失敗（以前はこれが成功に数えられていた）。
    def test_no_reply
      assert_raise(Ginseng::GatewayError) {publish_with(nil, nil)}
    end

    # ⚠ ほかのイベントへの `OK` を、このイベントの受理と読まない。
    def test_ok_for_other_event
      assert_raise(Ginseng::GatewayError) {publish_with(OTHER_EVENT, OTHER_EVENT)}
    end

    def test_closed
      assert_raise(Ginseng::GatewayError) {publish_with(CLOSE, CLOSE)}
    end

    private

    def publish_with(*replies)
      shrieker = NostrShrieker.new(private_key: Nostr::Keygen.new.generate_private_key.to_s, relays: RELAYS)
      queue = Thread::Queue.new(replies)
      shrieker.define_singleton_method(:create_client) {FakeClient.new(queue.pop)}
      shrieker.define_singleton_method(:publish_timeout) {0.5}
      event = shrieker.send(:user).create_event(kind: Nostr::EventKind::TEXT_NOTE, content: 'test')
      shrieker.send(:publish, event)
    end
  end
end
