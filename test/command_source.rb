module TomatoToot
  class CommandSourceTest < Test::Unit::TestCase
    def test_command
      Source.all do |source|
        next unless source.is_a?(CommandSource)
        assert_kind_of(Ginseng::CommandLine, source.command)
      end
    end
  end
end
