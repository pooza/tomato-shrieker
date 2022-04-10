module TomatoShrieker
  class LemmyTestCaseFilter < TestCaseFilter
    def active?
      return Source.all.none? {|s| s.test? && s.lemmy}
    end
  end
end
