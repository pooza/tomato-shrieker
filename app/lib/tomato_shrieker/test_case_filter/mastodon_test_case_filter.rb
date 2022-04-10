module TomatoShrieker
  class MastodonTestCaseFilter < TestCaseFilter
    def active?
      return Source.all.none? {|s| s.test? && s.mastodon?}
    end
  end
end
