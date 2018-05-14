require 'tomato-toot/json_renderer'

module TomatoToot
  class JSONRendererTest < Test::Unit::TestCase
    def test_to_s
      renderer = JSONRenderer.new
      renderer.message = {test: 123, null: nil}
      assert_equal(renderer.to_s, '{"test":123,"null":null}')
    end
  end
end
