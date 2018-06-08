require 'tomato-toot/webhook'
require 'open-uri'
require 'httparty'

module TomatoToot
  class ServerTest < Test::Unit::TestCase
    def setup
      return unless @hook = Webhook.all.first
      @root = URI.parse(@hook.hook_url)
    end

    def test_webhook_toot
      Webhook.all.each do |webhook|
        result = HTTParty.post(webhook.hook_url, {
          body: {text: '木の水晶球'}.to_json,
          headers: {'Content-Type' => 'application/json'},
          ssl_ca_file: File.join(ROOT_DIR, 'cert/cacert.pem'),
        })
        assert_true(result.response.is_a?(Net::HTTPOK))
        assert_equal('木の水晶球', result.parsed_response['response']['text'])

        result = HTTParty.post(webhook.hook_url, {
          body: {body: '武田信玄'}.to_json,
          headers: {'Content-Type' => 'application/json'},
          ssl_ca_file: File.join(ROOT_DIR, 'cert/cacert.pem'),
        })
        assert_true(result.response.is_a?(Net::HTTPOK))
        assert_equal('武田信玄', result.parsed_response['response']['text'])
      end
    end

    def test_not_found
      return unless @root
      uri = @root.clone
      uri.path = '/not_found'
      begin
        uri.open
      rescue OpenURI::HTTPError => e
        assert_equal(e.message, '404 Not Found')
      end
    end
  end
end
