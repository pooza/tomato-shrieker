module TomatoShrieker
  # 🔴 **直接経路（MastodonShrieker / MisskeyShrieker）を実インスタンス相手に動かす (#1451)。**
  #
  # 運用者は Webhook（モロヘイヤ経由）しか使っていないが、Mastodon / Misskey の API へ直接投稿している
  # 外部ユーザーがいる（docs/CLAUDE.md「投稿先ごとのテスト厚みの非対称」）。`test/sources/` の
  # ダミー宛先は形だけで、`Source#deliver` もテストでは配信しない＝**直接経路は API を一度も叩いていない**。
  #
  # 📌 chubo2 の fedi-test-harness（バニラの Mastodon / Misskey）が書き出す `.env.test` を読み込んで
  # 走らせる。⚠ 環境変数が無ければ（CI・ハーネスを立てていない手元）ケースごと省略する。
  #
  #   set -a; source ~/repos/chubo2/fedi-test-harness/mastodon/.env.test; set +a
  #   set -a; source ~/repos/chubo2/fedi-test-harness/misskey/.env.test; set +a
  #   bundle exec rake test
  #
  # ⚠ Shrieker を直接叩く（`Source#deliver` はテストでは配信を飛ばすので通らない）。投稿したものは
  # API で読み返して中身を確かめ、最後に消す。
  module FediHarness
    TEXT = 'tomato-shrieker の直接経路のテスト (#1451)'.freeze
    TAG = 'tomato_harness'.freeze

    def harness_source(dest)
      # ⚠ ハーネスは localhost で待ち受ける。この 1 本だけローカルへの接続を許す（TestCase が毎テスト戻す）。
      WebMock.disable_net_connect!(allow_localhost: true)
      return TextSource.new(
        'id' => "__test_fedi_harness_#{dest.keys.first}__",
        'source' => {'text' => "#{TEXT} #{Time.now.to_f}"},
        'dest' => dest.merge('tags' => [TAG]),
      )
    end

    def exec_shrieker(source, shrieker)
      return shrieker.exec(template: source.create_template, visibility: 'unlisted')
    end
  end

  class FediHarnessMastodonTest < TestCase
    include FediHarness

    def disable?
      return true unless ENV['MASTODON_URL'].present? && ENV['MASTODON_ACCESS_TOKEN'].present?
      return super
    end

    # 投稿し、読み返した本文に、テンプレートの本文とタグが載っていること。公開範囲も渡っていること。
    def test_exec_posts_status
      source = harness_source('mastodon' => {'url' => ENV.fetch('MASTODON_URL'), 'token' => ENV.fetch('MASTODON_ACCESS_TOKEN')})
      shrieker = source.mastodon
      response = exec_shrieker(source, shrieker)
      status = shrieker.fetch_status(response['id'])

      assert_include(status['content'], TEXT)
      assert_include(status['content'], TAG)
      assert_equal('unlisted', status['visibility'])
    ensure
      shrieker&.delete_status(response['id']) if response&.dig('id')
    end

    # ソースの `spoiler_text` が CW として渡ること。
    def test_exec_posts_spoiler_text
      source = harness_source(
        'mastodon' => {'url' => ENV.fetch('MASTODON_URL'), 'token' => ENV.fetch('MASTODON_ACCESS_TOKEN')},
        'spoiler_text' => 'CW のテスト',
      )
      shrieker = source.mastodon
      response = exec_shrieker(source, shrieker)

      assert_equal('CW のテスト', shrieker.fetch_status(response['id'])['spoiler_text'])
    ensure
      shrieker&.delete_status(response['id']) if response&.dig('id')
    end

    # トークンが通らなければ例外（`Source#deliver` が宛先の失敗として数える形）。
    def test_exec_with_bad_token
      source = harness_source('mastodon' => {'url' => ENV.fetch('MASTODON_URL'), 'token' => 'invalid-token'})

      assert_raise(Ginseng::GatewayError) {exec_shrieker(source, source.mastodon)}
    end
  end

  # 🔴 **モロヘイヤ経由（WebhookShrieker → モロヘイヤ → Mastodon）を実物で通す (#1452)。**
  #
  # 本番の Mastodon 宛ては全部この経路なのに、テストは `WebhookShrieker` の body を組むところまでで、
  # モロヘイヤが受け取れる形かは一度も確かめていなかった。ハーネスの Mastodon の前段に
  # `test/harness/mulukhiya.sh up` でモロヘイヤを立て、その `.env.test` も読み込んで走らせる。
  # ⚠ 環境変数が無ければ省略する。
  class FediHarnessWebhookTest < TestCase
    include FediHarness

    def disable?
      return true unless ENV['MULUKHIYA_WEBHOOK_URL'].present?
      return true unless ENV['MASTODON_URL'].present? && ENV['MASTODON_ACCESS_TOKEN'].present?
      return super
    end

    # 読み返しと後片付けに使う（投稿はモロヘイヤが test アカウントとして行う）。
    def mastodon
      @mastodon ||= harness_source(
        'mastodon' => {'url' => ENV.fetch('MASTODON_URL'), 'token' => ENV.fetch('MASTODON_ACCESS_TOKEN')},
      ).mastodon
    end

    def exec_webhook(source, url = ENV.fetch('MULUKHIYA_WEBHOOK_URL'))
      return WebhookShrieker.create(url).exec(template: source.create_template, visibility: 'unlisted')
    end

    # 本文とタグが届き、リクエストごとの公開範囲（`visibility`）がモロヘイヤの既定より優先されること。
    def test_exec_posts_status
      response = exec_webhook(harness_source('hooks' => [ENV.fetch('MULUKHIYA_WEBHOOK_URL')]))
      status = mastodon.fetch_status(response['id'])

      assert_include(status['content'], TEXT)
      assert_include(status['content'], TAG)
      assert_equal('unlisted', status['visibility'])
      assert_match(/\Amulukhiya/, status.dig('application', 'name'))
    ensure
      mastodon&.delete_status(response['id']) if response&.dig('id')
    end

    # ソースの `spoiler_text` が CW として渡ること。
    def test_exec_posts_spoiler_text
      source = harness_source('hooks' => [ENV.fetch('MULUKHIYA_WEBHOOK_URL')], 'spoiler_text' => 'CW のテスト')
      response = exec_webhook(source)

      assert_equal('CW のテスト', mastodon.fetch_status(response['id'])['spoiler_text'])
    ensure
      mastodon&.delete_status(response['id']) if response&.dig('id')
    end

    # 誰のものでもない digest は 404（`Source#deliver` が宛先の失敗として数える形）。
    def test_exec_with_unknown_digest
      url = ENV.fetch('MULUKHIYA_WEBHOOK_URL').sub(%r{/webhook/\h+\z}, "/webhook/#{'0' * 64}")

      assert_raise(Ginseng::GatewayError) {exec_webhook(harness_source('hooks' => [url]), url)}
    end
  end

  class FediHarnessMisskeyTest < TestCase
    include FediHarness

    def disable?
      return true unless ENV['MISSKEY_URL'].present? && ENV['MISSKEY_ACCESS_TOKEN'].present?
      return super
    end

    def test_exec_posts_note
      source = harness_source('misskey' => {'url' => ENV.fetch('MISSKEY_URL'), 'token' => ENV.fetch('MISSKEY_ACCESS_TOKEN')})
      shrieker = source.misskey
      response = exec_shrieker(source, shrieker)
      id = response.dig('createdNote', 'id')
      note = shrieker.fetch_note(id)

      assert_include(note['text'], TEXT)
      assert_include(note['text'], TAG)
      assert_equal('home', note['visibility'])
    ensure
      shrieker&.delete_note(id) if id
    end

    def test_exec_posts_spoiler_text
      source = harness_source(
        'misskey' => {'url' => ENV.fetch('MISSKEY_URL'), 'token' => ENV.fetch('MISSKEY_ACCESS_TOKEN')},
        'spoiler_text' => 'CW のテスト',
      )
      shrieker = source.misskey
      id = exec_shrieker(source, shrieker).dig('createdNote', 'id')

      assert_equal('CW のテスト', shrieker.fetch_note(id)['cw'])
    ensure
      shrieker&.delete_note(id) if id
    end

    def test_exec_with_bad_token
      source = harness_source('misskey' => {'url' => ENV.fetch('MISSKEY_URL'), 'token' => 'invalid-token'})

      assert_raise(Ginseng::GatewayError) {exec_shrieker(source, source.misskey)}
    end
  end
end
