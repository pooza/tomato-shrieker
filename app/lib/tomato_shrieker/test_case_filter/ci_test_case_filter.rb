module TomatoShrieker
  class CITestCaseFilter < TestCaseFilter
    def active?
      return Environment.ci?
    end
  end
end
