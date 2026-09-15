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
