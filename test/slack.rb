require 'tomato-toot/slack'

module TomatoToot
  class SlackTest < Test::Unit::TestCase
    def test_all
      Slack.all do |slack|
        assert_true(slack.is_a?(Slack))
      end
    end

    def test_say
      Slack.all do |slack|
        result = slack.say({text: 'hoge'})
        assert_true(result.response.is_a?(Net::HTTPOK))
        assert_equal(result.parsed_response['response']['text'], "{\n  \"text\": \"hoge\"\n}")
      end
    end
  end
end
