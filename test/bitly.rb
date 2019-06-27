module TomatoToot
  class BitlyTest < Test::Unit::TestCase
    def test_shorten
      return unless Config.instance['/bitly/token']
      bitly = Bitly.new
      assert(bitly.shorten('https://bitly.com/').is_a?(Ginseng::URI))
    rescue Ginseng::ConfigError
      assert(true)
    end
  end
end
