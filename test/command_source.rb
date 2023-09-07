module TomatoShrieker
  class CommandSourceTest < TestCase
    def test_command
      CommandSource.all.reject(&:disable?).each do |source|
        assert_kind_of(Ginseng::CommandLine, source.command)
        source.command.exec

        assert_predicate(source.command.status, :zero?)
      end
    end

    def test_delimiter
      CommandSource.all.reject(&:disable?).each do |source|
        assert_kind_of(Regexp, source.delimiter)
      end
    end

    def test_bundler?
      CommandSource.all.reject(&:disable?).each do |source|
        assert_boolean(source.bundler?)
      end
    end
  end
end
