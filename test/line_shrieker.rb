module TomatoShrieker
  class LineShriekerTest < TestCase
    def setup
      @template = Template.new('common')
      @template[:status] = Time.now.to_s
      @template[:source] = Source.all.find {|v| v.id == 'line_test'}
    end

    def test_exec
      Source.all.select(&:test?).select(&:line).each do |source|
        source.clear
        source.exec
      end
    end
  end
end
