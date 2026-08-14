module TomatoShrieker
  module Refines
    class ::String
      def encrypt
        return Crypt.new.encrypt(self)
      end

      def decrypt
        return Crypt.new.decrypt(self)
      end

      # JSON に載せられる UTF-8 へ倒す (#1469)。
      #
      # ⚠ ASCII-8BIT の文字列では valid_encoding? が常に true になるので、
      # 検査で分岐せず無条件に force_encoding してから scrub する。
      def to_utf8
        return dup.force_encoding(Encoding::UTF_8).scrub
      end
    end
  end
end
