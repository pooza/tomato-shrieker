module TomatoShrieker
  class LineShriekerTest < TestCase
    def setup
      @template = Template.new('common')
      @template[:status] = Time.now.to_s
      @template[:source] = Source.all.find {|v| v.id == 'line_test'}
    end

    def test_exec
      assert_equal(200, @template[:source].line.exec(template: @template).code)
    end
  end
end
