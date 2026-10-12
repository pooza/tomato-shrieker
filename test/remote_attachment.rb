module TomatoShrieker
  # #1666: 添付（フィードの enclosure ＝ 第三者が書ける URL）の扱い。
  #
  # ⚠ 直接経路（Mastodon / Misskey）のテスト用ソースは手元にも CI にも無いので、
  # ソースを介さず Shrieker を直に組み立てる（`disable?` を持たない）。
  class RemoteAttachmentTest < TestCase
    INTERNAL = [
      'http://127.0.0.1/a.png',
      'http://169.254.169.254/latest/meta-data/',
      'http://localhost/a.png',
    ].freeze

    MIXED = ['good1', 'bad', 'good2'].freeze

    # ⚠ `spoiler_text` と `id` だけを持つ、ソースの代役。
    FakeSource = Struct.new(:id, :spoiler_text)

    # ⚠ Shrieker が触るのは `[]=`・`to_s`・`source` だけ。
    class FakeTemplate < Hash
      def source
        return FakeSource.new('__remote_attachment__', nil)
      end

      def to_s
        return 'body text'
      end
    end

    def shriekers
      return [
        MastodonShrieker.new('https://mstdn.example.com', 'token'),
        MisskeyShrieker.new('https://misskey.example.com', 'token'),
      ]
    end

    # 🔴 内部ホストを指す添付は、**要求を 1 本も出さずに**落ちる。
    # ⚠ gem の既定（ginseng-fediverse 6.0.0）に頼っているので、版を戻すとここが赤くなる。
    def test_internal_hosts_are_dropped_without_request
      shriekers.each do |shrieker|
        attachments = INTERNAL.map {|v| {image_url: v}}

        assert_empty(shrieker.upload_attachments(attachments), shrieker.class.to_s)
      end
      assert_not_requested(:any, /.*/)
    end

    # 取れた添付は残し、取れなかったものだけを落とす（順序も保つ）。
    def test_keeps_uploaded_attachments
      shriekers.each do |shrieker|
        shrieker.define_singleton_method(:upload_remote_resource) do |url, _params = {}|
          raise Ginseng::GatewayError, "Rejected host '#{url}'" if url.include?('bad')
          next "id:#{url}"
        end
        ids = shrieker.upload_attachments(MIXED.map {|v| {image_url: v}})

        assert_equal(['id:good1', 'id:good2'], ids, shrieker.class.to_s)
      end
    end

    # 🔴 **4.15.0 リリース前レビュー: 読めない `Location` の全文をログに出さない。**
    # ⚠ `URI::InvalidURIError` のメッセージは URL 全体を含み、読めない URL はログのマスクが
    # 素通しにする＝リダイレクト先の署名が残る。クラス名だけを出す。
    def test_dropped_log_does_not_leak_unparsable_location
      shriekers.each do |shrieker|
        logged = []
        fake = Object.new
        fake.define_singleton_method(:warn) {|values| logged.push(values)}
        shrieker.define_singleton_method(:logger) {fake}
        shrieker.define_singleton_method(:upload_remote_resource) do |_url, _params = {}|
          raise ::URI::InvalidURIError, 'bad URI (is not URI?): "http://exa mple.com/a b?token=SECRET"'
        end

        assert_empty(shrieker.upload_attachments([{image_url: 'https://cdn.example.com/a.png?sig=QUERY'}]))
        assert_equal(1, logged.size)
        assert_equal('URI::InvalidURIError', logged.first[:error])
        assert_equal('cdn.example.com', logged.first[:host])
        assert_not_include(logged.first.to_s, 'SECRET')
        assert_not_include(logged.first.to_s, 'QUERY')
      end
    end

    # ⚠ ほかの失敗は `Package.error_message` を通す（クラス名つき）。
    def test_dropped_log_carries_error_class
      shrieker = shriekers.first
      logged = []
      fake = Object.new
      fake.define_singleton_method(:warn) {|values| logged.push(values)}
      shrieker.define_singleton_method(:logger) {fake}
      shrieker.upload_attachments([{image_url: 'http://127.0.0.1/a.png'}])

      assert_match(/\AGinseng::GatewayError: Rejected host/, logged.first[:error])
    end

    # ⚠ 握るのは「取れない・上げられない」だけ。実装の誤りまで握らない。
    def test_does_not_swallow_unexpected_errors
      shriekers.each do |shrieker|
        shrieker.define_singleton_method(:upload_remote_resource) do |_url, _params = {}|
          raise NoMethodError, 'bug'
        end

        assert_raise(NoMethodError) {shrieker.upload_attachments([{image_url: 'x'}])}
      end
    end

    # 🔴 添付が全部落ちても、**本文は投稿する**（添付の失敗で投稿ごと落とさない）。
    def test_exec_posts_body_when_attachments_are_dropped
      toot = stub_request(:post, 'https://mstdn.example.com/api/v1/statuses')
        .with {|req| req.body.include?('body text')}
        .to_return(status: 200, body: {id: '1'}.to_json, headers: {'Content-Type' => 'application/json'})
      note = stub_request(:post, 'https://misskey.example.com/api/notes/create')
        .with {|req| req.body.include?('body text')}
        .to_return(status: 200, body: {createdNote: {id: '1'}}.to_json, headers: {'Content-Type' => 'application/json'})

      shriekers.each do |shrieker|
        shrieker.exec(
          template: FakeTemplate.new,
          visibility: 'public',
          attachments: INTERNAL.map {|v| {image_url: v}},
        )
      end

      assert_requested(toot, times: 1)
      assert_requested(note, times: 1)
      assert_not_requested(:any, /127\.0\.0\.1|169\.254|localhost/)
    end
  end
end
