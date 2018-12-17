module TomatoToot
  class JSONRendererTest < Test::Unit::TestCase
    def setup
      @renderer = JSONRenderer.new
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
      @renderer.message = '123'
      assert_equal(@renderer.to_s, '"123"')
    end
  end
end
