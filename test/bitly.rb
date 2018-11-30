module TomatoToot
  class BitlyTest < Test::Unit::TestCase
    def test_shorten
      return unless Config.instance['/bitly/token']
      bitly = Bitly.new
      assert_true(bitly.shorten('https://bitly.com/').is_a?(Addressable::URI))
    end
  end
end
