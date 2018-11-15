require 'open-uri'
require 'httparty'

module TomatoToot
  class ServerTest < Test::Unit::TestCase
    def test_webhook_toot
      Webhook.all do |webhook|
        result = HTTParty.post(webhook.hook_url, {
          body: {text: '木の水晶球'}.to_json,
          headers: {'Content-Type' => 'application/json'},
          ssl_ca_file: ENV['SSL_CERT_FILE'],
        })
        assert_true(result.response.is_a?(Net::HTTPOK))
        assert_equal('木の水晶球', result.parsed_response['text'])

        result = HTTParty.post(webhook.hook_url, {
          body: {body: '武田信玄'}.to_json,
          headers: {'Content-Type' => 'application/json'},
          ssl_ca_file: ENV['SSL_CERT_FILE'],
        })
        assert_true(result.response.is_a?(Net::HTTPOK))
        assert_equal('武田信玄', result.parsed_response['text'])
      end
    end

    def test_not_found
      return unless @hook = Webhook.all.first
      uri = URI.parse(@hook.hook_url)
      uri.path = '/not_found'
      begin
        uri.open
      rescue OpenURI::HTTPError => e
        assert_equal(e.message, '404 Not Found')
      end
    end
  end
end
