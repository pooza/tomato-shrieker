module TomatoShrieker
  class PiefedShriekerTest < TestCase
    def disable?
      return true if Source.all.none? {|s| s.test? && s.piefed?}
      return super
    end

    def test_exec
      Source.all.select(&:test?).select(&:piefed).each do |source|
        source.clear
        assert_nothing_raised {source.exec}
      end
    end

    def test_templates
      Source.all.select(&:test?).select(&:piefed).each do |source|
        assert_kind_of(Hash, source.templates)
        assert_kind_of(Template, source.templates[:default])
      end
    end
  end
end

module TomatoShrieker
  # ⚠ 上の PiefedShriekerTest は dest に piefed を持つテスト用ソースが手元に無いと
  # `disable?` で丸ごと落ちる (#1520)。login の遅延・リダイレクト・投稿本文の組み立ては
  # 環境に依らず見たいので、webmock で閉じた独立のテストケースにする。
  class PiefedShriekerOfflineTest < TestCase
    PARAMS = {
      host: 'piefed.example.com',
      user_id: 'user@example.com',
      password: 'password',
      community_id: 1,
    }.freeze

    def setup
      WebMock.enable!
      WebMock.disable_net_connect!
      @stub = stub_request(:post, %r{/user/login}).to_return(
        status: 200,
        body: '{"jwt":"dummy"}',
        headers: {'Content-Type' => 'application/json'},
      )
    end

    def teardown
      WebMock.allow_net_connect!
      WebMock.disable!
      super
    end

    # #1514: 構築時に無条件で login すると、投稿しないケース（設定の読み込み・
    # source list・テストの初期化）でも認証 API を叩き、429 を踏みやすくなる。
    def test_does_not_login_on_initialize
      PiefedShrieker.new(PARAMS)

      assert_not_requested(@stub)
    end

    def test_logs_in_on_demand
      shrieker = PiefedShrieker.new(PARAMS)
      shrieker.login

      assert_requested(@stub, times: 1)
    end

    # ⚠ 上流の Service#login は `return if @jwt` を持つ。exec のたびに叩き直さない。
    def test_does_not_login_twice
      shrieker = PiefedShrieker.new(PARAMS)
      2.times {shrieker.login}

      assert_requested(@stub, times: 1)
    end

    # #1752: ginseng-piefed 0.6.0 はログインの失敗をインスタンスの寿命の間覚える。
    # 回復は次の run の作り直しに任せている（`Source#reset_shriekers`）。
    def test_login_failure_lasts_until_the_shrieker_is_recreated
      stub = stub_request(:post, %r{/user/login}).to_return(
        {status: 401, body: '{}', headers: {'Content-Type' => 'application/json'}},
        {status: 200, body: '{"jwt":"dummy"}', headers: {'Content-Type' => 'application/json'}},
      )
      shrieker = PiefedShrieker.new(PARAMS)
      assert_raise(Ginseng::AuthError) {shrieker.login}
      assert_raise(Ginseng::AuthError) {shrieker.login}

      assert_requested(stub, times: 1)
      assert_nothing_raised {PiefedShrieker.new(PARAMS).login}
      assert_requested(stub, times: 2)
    end

    # #1631: `include Package` が無いと `http_class` が gem 既定の `Ginseng::HTTP` に
    # 倒れ、tomato の `/http/retry/limit`・User-Agent・マスクが PieFed 宛にだけ効かない。
    def test_uses_package_http
      http = PiefedShrieker.new(PARAMS).http

      assert_instance_of(HTTP, http)
      assert_equal(config['/http/retry/limit'], http.retry_limit)
    end

    # #1620: 資格情報（JWT）を運ぶ要求がリダイレクト先へ持ち越されないこと。
    def test_does_not_follow_redirect
      stub_request(:post, %r{/api/[^/]+/post}).to_return(
        status: 307,
        headers: {'Location' => 'https://evil.example.com/post'},
      )
      evil = stub_request(:post, 'https://evil.example.com/post')
      shrieker = PiefedShrieker.new(PARAMS)
      shrieker.login

      assert_raise(Ginseng::GatewayError) do
        shrieker.http.post("/api/#{shrieker.api_version}/post", {
          body: {title: 'x'},
          headers: {'Authorization' => 'Bearer dummy'},
        })
      end
      assert_not_requested(evil)
    end

    # 🔴 **#1673: タグは本文にもタイトルにも並べない。他の宛先に左右されない (#1484)。**
    # ⚠ 以前は `[:tag]` を立てずに描画していたので、単独なら付かず、Mastodon / Misskey と
    # 併用なら付き、Line と併用なら落ちていた。
    def test_post_data_has_no_tags
      [nil, true, false].each do |leaked|
        template = tagged_source.create_template(:default, 'フィクスチャの本文')
        template[:tag] = leaked
        data = PiefedShrieker.new(PARAMS).send(:post_data, template)

        assert_not_include(data[:body], '#fixture_tag', "body（前の宛先のフラグ: #{leaked.inspect}）")
        assert_not_include(data[:title], '#fixture_tag', "title（前の宛先のフラグ: #{leaked.inspect}）")
        assert_include(data[:body], 'フィクスチャの本文')
        assert_include(data[:title], 'フィクスチャの本文')
        assert_equal(1, data[:community_id])
      end
    end

    # ⚠ 描画は 1 回だけ。URL の控えも同じ描画から取る。
    def test_post_data_renders_once
      template = tagged_source.create_template(:default, '本文 https://example.com/a')
      rendered = 0
      original = template.method(:to_s)
      template.define_singleton_method(:to_s) do
        rendered += 1
        original.call
      end
      data = PiefedShrieker.new(PARAMS).send(:post_data, template)

      assert_equal(1, rendered)
      assert_equal('https://example.com/a', data[:url])
      assert_not_include(data[:body], 'https://example.com/a')
    end

    # 🔴 **#1671: タイトルに URL と末尾の空白を残さない。**URL を残すと上限で URL の途中に `…` が入る。
    def test_post_data_title_has_no_urls
      template = tagged_source.create_template(:default, "行1\n行2 https://example.com/a https://example.com/ab")
      data = PiefedShrieker.new(PARAMS).send(:post_data, template)

      assert_equal('行1 行2', data[:title])
    end

    def test_post_data_title_is_stripped
      data = PiefedShrieker.new(PARAMS).send(:post_data, tagged_source.create_template(:default, "短い本文\n"))

      assert_equal('短い本文', data[:title])
    end

    # ⚠ URL だけの本文ではタイトルが空になるので、最初の URL を使う。
    def test_post_data_title_falls_back_to_url
      template = tagged_source.create_template(:default, 'https://example.com/a')
      data = PiefedShrieker.new(PARAMS).send(:post_data, template)

      assert_equal('https://example.com/a', data[:title])
    end

    # 🔴 **#1671: 本文の URL は長い順に消す。**短いほうを先に消すと、長い URL の残りが本文に残る。
    def test_post_data_removes_longer_urls_first
      template = tagged_source.create_template(:default, '本文 https://example.com/a https://example.com/ab')
      data = PiefedShrieker.new(PARAMS).send(:post_data, template)

      assert_not_include(data[:body], 'example.com')
      assert_equal('本文', data[:body].strip)
    end

    # #1671: URL の直後の句点から先を URL ごと消さない（ginseng-core 4.1.0・pooza/ginseng-core#721）。
    def test_post_data_keeps_text_after_url
      template = tagged_source.create_template(:default, '本文 https://example.com/a。次の文')
      data = PiefedShrieker.new(PARAMS).send(:post_data, template)

      assert_equal('本文 。次の文', data[:title])
      assert_include(data[:body], '。次の文')
    end

    def stub_create(body = {post_view: {post: {id: 123}}})
      return stub_request(:post, %r{/api/[^/]+/post\z}).to_return(
        status: 200, body: body.to_json, headers: {'Content-Type' => 'application/json'},
      )
    end

    def stub_edit(status = 200)
      return stub_request(:put, %r{/api/[^/]+/post\z}).to_return(
        status:, body: '{}', headers: {'Content-Type' => 'application/json'},
      )
    end

    def exec_with(source)
      return PiefedShrieker.new(PARAMS).exec(template: source.create_template(:default, '本文'))
    end

    # 🔴 **#1673: タグは、作成した投稿を編集して付ける。**PieFed の作成 API はタグを受け取らず、
    # 本文の `#tag` も拾わない。
    def test_exec_attaches_tags_by_editing_the_post
      create = stub_create
      edit = stub_edit
      exec_with(tagged_source(['fixture_tag', 'second']))

      assert_requested(create, times: 1)
      assert_requested(:post, %r{/api/[^/]+/post\z}) {|req| !req.body.include?('fixture_tag')}
      assert_requested(edit, times: 1)
      assert_requested(:put, %r{/api/[^/]+/post\z}) do |req|
        params = JSON.parse(req.body)
        params['post_id'].to_s == '123' && params['tags'] == 'fixture_tag,second' &&
          req.headers['Authorization'] == 'Bearer dummy' && (params.keys - ['post_id', 'tags']).empty?
      end
    end

    # タグの無いソースでは、編集の要求を出さない。
    def test_exec_does_not_edit_without_tags
      stub_create
      edit = stub_edit
      exec_with(tagged_source([]))

      assert_not_requested(edit)
    end

    # 🔴 **タグが付かなくても、投稿は成功として返す。**⚠ 例外にすると配信の失敗に数えられ、
    # もう出ている投稿が再実行で二重になる。
    def test_exec_succeeds_when_tags_are_not_attached
      stub_create
      edit = stub_edit(422)

      assert_nothing_raised {exec_with(tagged_source)}
      assert_requested(edit, times: 1)
    end

    # #1687: タグが付かなかったことは warn だけでなく Sentry へも残す。
    def test_tags_not_attached_goes_to_sentry
      stub_create
      stub_edit(422)
      captured = []
      with_sentry_stub(captured) {exec_with(tagged_source)}

      assert_equal('tags not attached', captured.first[:message])
    end

    # 🔴 **#1679 の Codex P2: 投稿を作った後は、例外の種類を選ばずに握る。**
    # ⚠ 応答が JSON でない（`parsed_response` が文字列）と `dig` が `NoMethodError` を上げる。
    def test_exec_succeeds_when_response_is_not_json
      stub_request(:post, %r{/api/[^/]+/post\z}).to_return(status: 200, body: 'OK')
      edit = stub_edit

      assert_nothing_raised {exec_with(tagged_source)}
      assert_not_requested(edit)
    end

    # 🔴 **タグを求めるところで落ちるなら、投稿を作る前に落とす**（再実行で二重にならない）。
    def test_exec_resolves_tags_before_creating_the_post
      create = stub_create
      source = tagged_source
      source.define_singleton_method(:create_tags) {|_status| raise 'tagging failed'}

      assert_raise(RuntimeError) {exec_with(source)}
      assert_not_requested(create)
    end

    # ⚠ 応答から投稿の id が読めないときも同じ（編集は出さない）。
    def test_exec_succeeds_when_post_id_is_missing
      stub_create({})
      edit = stub_edit

      assert_nothing_raised {exec_with(tagged_source)}
      assert_not_requested(edit)
    end

    # 🔴 **4.15.0 リリース前レビュー: 本文（`status`）が無いテンプレートで `create_tags` を呼ばない。**
    # ⚠ 予定（`IcalendarSource`）のテンプレートは本文を持たない。リモートのタグ付けが有効だと
    # モロヘイヤへ nil を渡して `NoMethodError` になり、予定 1 件ごとに PieFed 宛が失敗していた。
    # ⚠ `calendar.erb` が並べるのは `source.tags` なので、そちらに合わせる。
    def test_tags_of_uses_source_tags_without_status
      source = tagged_source(['fixture_tag', 'second'])
      source.define_singleton_method(:create_tags) {|_status| raise 'create_tags は呼ばない'}
      template = source.create_template(:default, nil)
      template[:entry] = {title: '予定'}
      template[:status] = nil

      assert_equal(['fixture_tag', 'second'], PiefedShrieker.new(PARAMS).send(:tags_of, template))
    end

    # ⚠ 本文があれば `create_tags`（リモートのタグ付けを含む）、エントリがタグを持てばそちら。
    def test_tags_of_follows_template_kind
      source = tagged_source
      source.define_singleton_method(:create_tags) {|_status| ['#from_create_tags']}
      shrieker = PiefedShrieker.new(PARAMS)

      assert_equal(['from_create_tags'], shrieker.send(:tags_of, source.create_template(:default, '本文')))
      template = source.create_template(:default, '本文')
      template[:entry] = Struct.new(:tags).new(['#from_entry', '#from_entry'])

      assert_equal(['from_entry'], shrieker.send(:tags_of, template))
    end

    def tagged_source(tags = ['fixture_tag'])
      return TextSource.new(
        'id' => '__test_piefed_tags__',
        'source' => {'text' => 'フィクスチャの本文'},
        'schedule' => {'every' => '1d'},
        'dest' => {'tags' => tags, 'piefed' => PARAMS.transform_keys(&:to_s)},
      )
    end
  end
end
