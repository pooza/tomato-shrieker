require 'tomato-toot/webhook'
require 'addressable/uri'

module TomatoToot
  class WebhookTest < Test::Unit::TestCase
    def test_all
      Webhook.all do |hook|
        assert_true(hook.is_a?(Webhook))
      end
    end

    def test_search
      Webhook.all do |hook|
        assert_not_nil(Webhook.search(hook.digest))
      end
    end

    def test_digest
      Webhook.all do |hook|
        assert_false(hook.digest.empty?)
        assert_false(hook.digest.nil?)
      end
    end

    def test_mastodon_url
      Webhook.all do |hook|
        assert_false(hook.mastodon_url.empty?)
        assert_false(hook.mastodon_url.nil?)
        assert_not_nil(Addressable::URI.parse(hook.mastodon_url))
      end
    end

    def test_token
      Webhook.all do |hook|
        assert_false(hook.token.empty?)
        assert_false(hook.token.nil?)
      end
    end

    def test_hook_url
      Webhook.all do |hook|
        assert_not_nil(Addressable::URI.parse(hook.hook_url))
      end
    end

    def test_to_json
      Webhook.all do |hook|
        assert_false(hook.to_json.empty?)
      end
    end
  end
end
