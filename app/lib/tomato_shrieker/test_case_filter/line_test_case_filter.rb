module TomatoShrieker
  class LineTestCaseFilter < TestCaseFilter
    def active?
      return Source.all.none?(&:line?)
    end
  end
end
