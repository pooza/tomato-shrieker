module TomatoShrieker
  class GoogleNewsTestCaseFilter < TestCaseFilter
    def active?
      return GoogleNewsSource.all.count.zero?
    end
  end
end
