require 'httparty'
require 'addressable/uri'

module TomatoToot
  class ServerTest < Test::Unit::TestCase
    def test_webhook_toot
      Webhook.all do |webhook|
        result = HTTParty.get(webhook.uri)
        assert_true(result.response.is_a?(Net::HTTPOK))

        result = HTTParty.post(webhook.uri, {
          body: {text: '木の水晶球'}.to_json,
          headers: {'Content-Type' => 'application/json'},
        })
        assert_true(result.response.is_a?(Net::HTTPOK))
        assert_equal('木の水晶球', result.to_h['text'])

        result = HTTParty.post(webhook.uri, {
          body: {body: '武田信玄'}.to_json,
          headers: {'Content-Type' => 'application/json'},
        })
        assert_true(result.response.is_a?(Net::HTTPOK))
        assert_equal('武田信玄', result.to_h['text'])
      end
    end

    def test_not_found
      return unless hook = Webhook.all.first
      uri = hook.uri.clone
      uri.path = '/not_found'
      assert_equal(HTTParty.get(uri).code, 404)
    end
  end
end
