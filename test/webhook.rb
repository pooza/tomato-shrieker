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
        assert_true(hook.digest.present?)
      end
    end

    def test_mastodon_uri
      Webhook.all do |hook|
        assert_true(hook.mastodon_uri.is_a?(Addressable::URI))
      end
    end

    def test_token
      Webhook.all do |hook|
        assert_true(hook.token.present?)
      end
    end

    def test_uri
      Webhook.all do |hook|
        assert_true(hook.uri.is_a?(Addressable::URI))
      end
    end

    def test_toot_tags
      Webhook.all do |hook|
        assert_true(hook.toot_tags.is_a?(Array))
      end
    end

    def test_to_json
      Webhook.all do |hook|
        assert_true(hook.to_json.present?)
      end
    end
  end
end
