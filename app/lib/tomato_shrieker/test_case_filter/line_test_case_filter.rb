module TomatoShrieker
  class LineTestCaseFilter < TestCaseFilter
    def active?
      return Source.all.none? {|s| s.line? && s.id == 'line_test'}
    end
  end
end
