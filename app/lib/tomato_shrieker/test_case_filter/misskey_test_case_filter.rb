module TomatoShrieker
  class MisskeyTestCaseFilter < TestCaseFilter
    def active?
      return Source.all.none? {|s| s.test? && s.misskey?}
    end
  end
end
