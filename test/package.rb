require 'tomato-toot/package'

module TomatoToot
  class PackageTest < Test::Unit::TestCase
    def test_name
      assert_equal(Package.name, 'tomato-toot')
    end
  end
end
