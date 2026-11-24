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

    # 🔴 #1825: エントリーのある投稿は `[prefix] 題` をスレッドのタイトルとして送る。
    def test_build_body_sends_entry_title
      body = tsunagal.build_body(template: template(nil, entry_title: 'v1.165.0', prefix: 'Release notes from synapse'))

      assert_equal('[Release notes from synapse] v1.165.0', body[:title])
      assert_equal(TEXT, body[:text], '本文は変えない')
    end

    def test_build_body_entry_title_without_prefix
      assert_equal('v1.165.0', tsunagal.build_body(template: template(nil, entry_title: 'v1.165.0'))[:title])
    end

    # ⚠ エントリーの無いソース（定型文・コマンド）は title を送らない＝本文の 1 行目がタイトル。
    def test_build_body_without_entry_sends_no_title
      assert_false(tsunagal.build_body(template: template(nil, prefix: 'x')).key?(:title))
      assert_false(tsunagal.build_body(template: template(nil, entry_title: ' ', prefix: 'x')).key?(:title))
    end

    # CW と title は独立に効く。
    def test_build_body_title_with_spoiler_text
      body = tsunagal.build_body(template: template(SPOILER, entry_title: '題', prefix: 'p'))

      assert_equal('[p] 題', body[:title])
      assert_equal("#{SPOILER}\n\n#{TEXT}", body[:text])
    end

    # 素の WebhookShrieker（モロヘイヤ宛て）には title を積まない。
    def test_plain_webhook_sends_no_title
      body = WebhookShrieker.new(HOOK_URL).build_body(template: template(nil, entry_title: '題', prefix: 'p'))

      assert_false(body.key?(:title))
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
    def template(spoiler_text, entry_title: nil, prefix: nil)
      source = Object.new
      source.define_singleton_method(:spoiler_text) {spoiler_text}
      source.define_singleton_method(:prefix) {prefix}
      entry = nil
      if entry_title
        entry = Object.new
        entry.define_singleton_method(:title) {entry_title}
      end
      stub = Object.new
      stub.define_singleton_method(:to_s) {TEXT}
      stub.define_singleton_method(:source) {source}
      stub.define_singleton_method(:entry) {entry}
      stub.define_singleton_method(:[]=) {|key, value| (@slots ||= {})[key] = value}
      stub.define_singleton_method(:[]) {|key| (@slots ||= {})[key]}
      return stub
    end
  end
end
