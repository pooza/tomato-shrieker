module TomatoShrieker
  class LineShriekerTest < TestCase
    def setup
      @config = Config.instance
      @template = Template.new('common')
      @template[:status] = Time.now.to_s
      @template[:source] = Source.all.find(&:line?)
    end

    def test_exec
      assert_equal(@template[:source].line.exec(template: @template).code, 200)
    end
  end
end
