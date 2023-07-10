module TomatoShrieker
  class ConfigText < TestCase
    def load
      config.load
    end

    def test_secure_dump
      assert_kind_of(Array, config.secure_dump)
    end
  end
end
