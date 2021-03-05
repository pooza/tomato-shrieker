module TomatoShrieker
  class LemmyTestCaseFilter < TestCaseFilter
    def active?
      return Source.all.none?(&:lemmy?)
    end
  end
end
