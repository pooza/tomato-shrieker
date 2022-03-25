module TomatoShrieker
  class LineShriekerTest < TestCase
    def setup
      @template = Template.new('common')
      @template[:status] = Time.now.to_s
      @template[:source] = Source.all.find {|v| v.id == 'line_test'}
    end

    def test_exec
      assert_equal(@template[:source].line.exec(template: @template).code, 200)
    end
  end
end
