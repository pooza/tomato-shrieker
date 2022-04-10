module TomatoShrieker
  class LineTestCaseFilter < TestCaseFilter
    def active?
      return Source.all.none? {|s| s.test? && s.line}
    end
  end
end
