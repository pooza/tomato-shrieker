module TomatoShrieker
  # 🔴 **保証そのものをテストする (#1468)。**
  #
  # ⚠⚠ **WebMock は `require` だけでは有効にならない。**`WebMock.enable!` を呼ぶまで
  # `stub_request` も `disable_net_connect!` も**無言で素通りする**。⚠ 書いたつもりで
  # 書けていない状態と、そもそも書いていない状態が、**テスト結果からは区別できない**。
  # だから「設定した」ではなく **「実際に止まる」** ことを確かめる。
  #
  # 📌 `pooza/makoto2` が同じ構成で実際に事故を起こしている（2026-07-30・ステージングへ
  # 10 通投稿）。そこで規約化された完了条件をこちらにも置く。
  class WebMockGuardTest < TestCase
    def test_unstubbed_get_is_blocked
      assert_raise(WebMock::NetConnectNotAllowedError) do
        Net::HTTP.get_response(URI.parse('https://unstubbed.example.com/feed'))
      end
    end

    # 🔴 **投稿を 1 通も出さない。**`disable?` で止まっているだけの Shrieker が何かの
    # 拍子に動き出しても、POST は stub されていないので必ずここで落ちる。
    def test_unstubbed_post_is_blocked
      assert_raise(WebMock::NetConnectNotAllowedError) do
        Net::HTTP.post(URI.parse('https://mastodon.example.com/api/v1/statuses'), 'status=x')
      end
    end

    # ⚠ 既定の stub（`stub_default_feeds`）が効いていること。⚠⚠ ここが外れると
    # 「外部へ出ない」ではなく「外部へ出て偶然通っている」に戻る。
    def test_default_feed_stub_is_applied
      body = Net::HTTP.get(URI.parse('https://www.youtube.com/feeds/videos.xml?channel_id=x'))

      assert_include(body, '<entry>')
    end
  end

  # 🔴 **#1468 の Codex P2: 汎用の `source/feed` を持つソースも塞がること。**
  #
  # ⚠⚠ サービス別のパターン（YouTube / GitHub / Google ニュース / ical）だけでは
  # **どこを指しているか分からない汎用ソースが漏れる**。`config/sources` は git 管理外で
  # **開発機ごとに中身が違う**ので、漏れると**その開発機でだけ `rake test` が落ちる**。
  class WebMockGenericFeedTest < TestCase
    FIXTURE_ID = '__test_webmock_generic__'.freeze
    FEED_URL = 'https://generic.example.org/path/to/rss'.freeze

    # teardown は異常終了で走らない。⚠ `config/sources/.gitignore` が `*` なので
    # 取り残しは git status にも出ず、次のスケジューラ起動で偽ソースとして登録される。
    at_exit do
      FileUtils.rm_f(File.join(Environment.dir, 'config/sources', "#{FIXTURE_ID}.yaml"))
    end

    def test_generic_feed_source_is_stubbed
      write_fixture
      config.reload
      # ⚠ setup の時点ではまだ存在しないソースなので、張り直してから確かめる。
      stub_default_feeds

      body = Net::HTTP.get(URI.parse(FEED_URL))

      assert_include(body, '<rss')
      assert_include(body, '<item>')
    ensure
      FileUtils.rm_f(path)
    end

    # ⚠ **#1595 の Codex P2: 設定済みソースの stub は、その URL だけを塞ぐこと。**
    # 素の前方一致だと `/rss` の stub が `/rssfeedback` や `/rss/admin` まで成功させ、
    # **誤った取得先への GET が遮断されない**。クエリ付きは同じ取得先として通す
    # （`IcalendarSource#uri` は毎回 `?t=<時刻>` を付ける）。
    def test_generic_feed_stub_is_bounded_to_source_url
      write_fixture
      config.reload
      stub_default_feeds

      assert_include(Net::HTTP.get(URI.parse("#{FEED_URL}?t=1")), '<rss')
      ["#{FEED_URL}feedback", "#{FEED_URL}/admin"].each do |url|
        assert_raise(WebMock::NetConnectNotAllowedError, url) do
          Net::HTTP.get_response(URI.parse(url))
        end
      end
    ensure
      FileUtils.rm_f(path)
    end

    private

    def path
      return File.join(Environment.dir, 'config/sources', "#{FIXTURE_ID}.yaml")
    end

    def write_fixture
      File.write(path, YAML.dump(
        'source' => {'feed' => FEED_URL},
        'schedule' => {'every' => '1d'},
        'dest' => {'hooks' => ['https://example.com/hook']},
      ))
    end
  end

  # 🔴🔴 **サブクラスが `def setup` を書いても保護が外れないこと (#1468)。**
  #
  # ⚠⚠ 共通処理を `def setup` に置くと、**サブクラスが `setup` を定義して `super` を
  # 忘れた瞬間に外れる**。しかも**外れても落ちない**ので気付けない（現に
  # `test/entry.rb` / `test/source_run_log.rb` は `def setup` を持つ）。
  # `setup do ... end` コールバックで登録しているのが要点で、これはその回帰テスト。
  class WebMockGuardWithoutSuperTest < TestCase
    # ⚠ わざと `super` を呼ばない。
    def setup
      @sentinel = true
    end

    # ⚠⚠ **見るのは「既定 stub が張られているか」。**`WebMock.enable!` と
    # `disable_net_connect!` は**グローバル状態で、先に走った別のテストの設定が残る**
    # ので、`def setup` に戻しても未 stub の遮断だけは偶然通ってしまう
    # （＝ そこを見ても判別できない）。🔴 **毎テスト張り直すのは stub のほう**で、
    # `teardown` の `WebMock.reset!` で消える。**ここが外れると、実サービスへの
    # リクエストが「未 stub」として落ちるか、最悪そのまま外へ出る。**
    def test_default_stubs_survive_subclass_setup_without_super
      assert_true(@sentinel, 'サブクラスの setup が走っていない（前提が崩れている）')
      body = Net::HTTP.get(URI.parse('https://www.youtube.com/feeds/videos.xml?channel_id=x'))

      assert_include(body, '<entry>')
    end

    def test_protection_survives_subclass_setup_without_super
      assert_raise(WebMock::NetConnectNotAllowedError) do
        Net::HTTP.get_response(URI.parse('https://unstubbed.example.com/feed'))
      end
    end
  end
end
