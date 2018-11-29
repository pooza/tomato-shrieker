require 'addressable/uri'

module TomatoToot
  class BitlyTest < Test::Unit::TestCase
    def test_shorten
      return unless Config.instance['/bitly/token']
      bitly = Bitly.new
      uri = bitly.shorten('https://bitly.com/')
      assert_not_nil(Addressable::URI.parse(uri))
    end
  end
end
