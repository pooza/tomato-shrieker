module TomatoShrieker
  class LemmyTestCaseFilter < TestCaseFilter
    def active?
      return Source.all.none? {|s| s.lemmy? && s.id == 'lemmy_test'}
    end
  end
end
