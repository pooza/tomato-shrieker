module TomatoShrieker
  module Refines
    class ::Time
      def xmlschema(fraction_digits = 0)
        fraction_digits = fraction_digits.to_i
        s = strftime('%FT%T')
        s << strftime(".%#{fraction_digits}N") if fraction_digits.positive?
        s << (utc? ? 'Z' : strftime('%:z'))
      end
    end
  end
end
