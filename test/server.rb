require 'tomato-toot/webhook'
require 'open-uri'
require 'httparty'

module TomatoToot
  class ServerTest < Test::Unit::TestCase
    def setup
      return unless @hook = Webhook.all.first
      @root = URI.parse(@hook.hook_url)
    end

    def test_about
      return unless @root
      uri = @root.clone
      uri.path = '/about'
      response = uri.open

      assert_equal(response.status.first, '200')
      assert_equal(response.meta['content-type'], 'application/json; charset=UTF-8')
    end

    def test_webhook_toot
      return unless @root
      result = HTTParty.post(@root, {
        body: {text: '木の水晶球'}.to_json,
        headers: {'Content-Type' => 'application/json'},
        ssl_ca_file: File.join(ROOT_DIR, 'cert/cacert.pem'),
      })
      assert_true(result.response.is_a?(Net::HTTPOK))
      assert_equal(result.parsed_response['response']['text'], '木の水晶球')

      result = HTTParty.post(@root, {
        body: {body: '武田信玄'}.to_json,
        headers: {'Content-Type' => 'application/json'},
        ssl_ca_file: File.join(ROOT_DIR, 'cert/cacert.pem'),
      })
      assert_true(result.response.is_a?(Net::HTTPOK))
      assert_equal(result.parsed_response['response']['text'], '武田信玄')
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
