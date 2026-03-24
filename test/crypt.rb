module TomatoShrieker
  class CryptTest < TestCase
    def test_password
      omit('/crypt/password not configured') unless Crypt.config?

      assert_kind_of(String, Crypt.password)
    end

    def test_config?
      omit('/crypt/password not configured') unless Crypt.config?

      assert_predicate(Crypt, :config?)
    end
  end
end
