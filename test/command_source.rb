module TomatoShrieker
  class CommandSourceTest < TestCase
    def test_command
      CommandSource.all do |source|
        assert_kind_of(Ginseng::CommandLine, source.command)
        source.command.exec
        source.command.stdout.split(source.delimiter).each do |status|
          next unless template = source.create_template(status)
          assert_kind_of(Template, template)
        end
        assert(source.command.status.zero?)
      end
    end

    def test_delimiter
      CommandSource.all do |source|
        assert_kind_of(Regexp, source.delimiter)
      end
    end

    def test_bundler?
      CommandSource.all do |source|
        assert_boolean(source.bundler?)
      end
    end
  end
end
