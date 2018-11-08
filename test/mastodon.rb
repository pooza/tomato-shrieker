module TomatoToot
  class MastodonTest < Test::Unit::TestCase
    def setup
      @mastodon = Webhook.all.first.mastodon
    end

    def test_search
      assert_false(@mastodon.nil?)
    end

    def test_toot
      response = @mastodon.toot('アイドル八犬伝')
      assert_equal(response.parsed_response['visibility'], 'public')

      response = @mastodon.toot('トランキライザーガン', {visibility: 'unlisted'})
      assert_equal(response.parsed_response['visibility'], 'unlisted')
    end
  end
end
