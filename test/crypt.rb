module TomatoShrieker
  class CryptTest < TestCase
    def test_password
      assert_kind_of(String, Crypt.password)
    end

    def test_config?
      assert_predicate(Crypt, :config?)
    end
  end
end
