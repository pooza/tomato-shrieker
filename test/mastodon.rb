module TomatoToot
  class MastodonTest < Test::Unit::TestCase
    def setup
      @mastodon = Webhook.all.first.mastodon
    end

    def test_search
      assert_true(@mastodon.is_a?(Mastodon))
    end

    def test_toot
      response = @mastodon.toot('アイドル八犬伝')
      assert_equal(response.to_h['visibility'], 'public')

      response = @mastodon.toot('トランキライザーガン', {visibility: 'unlisted'})
      assert_equal(response.to_h['visibility'], 'unlisted')
    end
  end
end
