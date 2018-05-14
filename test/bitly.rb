require 'tomato-toot/bitly'
require 'tomato-toot/config'
require 'addressable/uri'

module TomatoToot
  class BitlyTest < Test::Unit::TestCase
    def test_shorten
      return unless Config.instance['local']['bitly']
      bitly = Bitly.new
      url = bitly.shorten('https://bitly.com/')
      assert_not_nil(Addressable::URI.parse(url))
    end
  end
end
