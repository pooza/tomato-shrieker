module TomatoShrieker
  # #1493: matrix-webhook 宛で CW (spoiler_text) が黙って捨てられていた。
  class TsunagalWebhookShriekerTest < TestCase
    HOOK_URL = 'https://synapse.example.com/webhook'.freeze
    SPOILER = 'ネタバレ注意'.freeze
    TEXT = '本文です'.freeze

    # ⚠ 種別は `type` の明示だけで決める。`room_id` の有無のような暗黙判定に
    # 頼らない。`channel` は Slack でも意味を持つので判定に使えず、
    # 「Matrix 固有なのは room_id だけ」という前提に乗ると、**channel だけで
    # 書かれた宛先（本番の 3 ソースがこの形）を取りこぼす**。
    def test_create_selects_by_type
      assert_instance_of(
        TsunagalWebhookShrieker,
        WebhookShrieker.create('url' => HOOK_URL, 'type' => 'tsunagal', 'channel' => '#x:example.com'),
      )
    end

    def test_create_defaults_to_plain_webhook
      assert_instance_of(WebhookShrieker, WebhookShrieker.create(HOOK_URL))
      assert_instance_of(WebhookShrieker, WebhookShrieker.create('url' => HOOK_URL))
      # ⚠ room_id があっても type が無ければ素の Webhook のまま
      assert_instance_of(
        WebhookShrieker,
        WebhookShrieker.create('url' => HOOK_URL, 'room_id' => '!x:example.com'),
      )
    end

    # 🔴 本題。matrix-webhook は text / channel / room_id / format しか見ないので、
    # spoiler_text を積んでも黙って落ちる。本文の先頭へ畳んで送る。
    def test_build_body_folds_spoiler_text_into_text
      body = tsunagal.build_body(template: template(SPOILER))

      assert_nil(body[:spoiler_text], 'matrix-webhook が見ないキーは送らない')
      assert_include(body[:text], SPOILER)
      assert_include(body[:text], TEXT)
      assert_equal("#{SPOILER}\n\n#{TEXT}", body[:text])
    end

    # ⚠ CW が無いソースの本文を変えないこと。
    def test_build_body_without_spoiler_text
      assert_equal(TEXT, tsunagal.build_body(template: template(nil))[:text])
    end

    # 素の WebhookShrieker は従来どおり spoiler_text を別キーで送る
    # （モロヘイヤは解釈できる）。
    def test_plain_webhook_keeps_spoiler_text
      body = WebhookShrieker.new(HOOK_URL).build_body(template: template(SPOILER))

      assert_equal(SPOILER, body[:spoiler_text])
      assert_equal(TEXT, body[:text])
    end

    # ⚠⚠ #1484 の前提。build_body を override するとき tag を落とさないこと。
    def test_build_body_keeps_tag_flag
      tmpl = template(SPOILER)
      tsunagal.build_body(template: tmpl)

      assert_true(tmpl[:tag])
    end

    # channel / room_id はそのまま載せる（matrix-webhook 側の解釈）。
    def test_build_body_carries_room
      shrieker = WebhookShrieker.create(
        'url' => HOOK_URL, 'type' => 'tsunagal', 'channel' => '#matrix-news:example.com',
      )
      body = shrieker.build_body(template: template(SPOILER))

      assert_equal('#matrix-news:example.com', body[:channel])
    end

    # ⚠⚠ **Source の配線まで見る。** Shrieker 単体のテストだけだと、
    # `Source#shriekers` が `create` ではなく `new` を呼ぶ実装に戻っても気づけない。
    def test_source_shriekers_selects_tsunagal
      source = Source.new(
        'id' => '__test_tsunagal__',
        'dest' => {
          'hooks' => [
            {'url' => HOOK_URL, 'type' => 'tsunagal', 'channel' => '#x:example.com'},
            'https://mstdn.example.com/mulukhiya/webhook/deadbeef',
          ],
        },
      )

      assert_equal(
        [TsunagalWebhookShrieker, WebhookShrieker],
        source.shriekers.map(&:class),
      )
    end

    private

    def tsunagal
      return TsunagalWebhookShrieker.new(HOOK_URL)
    end

    # Template のふりをする最小の stub。⚠ 実 Template は ERB を評価するので、
    # ここでは「to_s が本文を返し、source.spoiler_text を持つ」ことだけ満たす。
    def template(spoiler_text)
      source = Object.new
      source.define_singleton_method(:spoiler_text) {spoiler_text}
      stub = Object.new
      stub.define_singleton_method(:to_s) {TEXT}
      stub.define_singleton_method(:source) {source}
      stub.define_singleton_method(:[]=) {|key, value| (@slots ||= {})[key] = value}
      stub.define_singleton_method(:[]) {|key| (@slots ||= {})[key]}
      return stub
    end
  end
end
