module TomatoToot
  class JsonRendererTest < Test::Unit::TestCase
    def setup
      @renderer = JsonRenderer.new
    end

    def test_status
      assert_equal(@renderer.status, 200)

      @renderer.status = 404
      assert_equal(@renderer.status, 404)
    end

    def test_type
      assert_equal(@renderer.type, 'application/json; charset=UTF-8')
    end

    def test_to_s
      @renderer.message = {test: 123, null: nil}
      assert_equal(@renderer.to_s, '{"test":123,"null":null}')
    end
  end
end
