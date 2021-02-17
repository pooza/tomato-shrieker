module TomatoShrieker
  class CommandSourceTest < TestCase
    def test_command
      CommandSource.all do |source|
        assert_kind_of(Ginseng::CommandLine, source.command)
      end
    end

    def test_delimiter
      CommandSource.all do |source|
        assert_kind_of(Regexp, source.delimiter)
      end
    end
  end
end
