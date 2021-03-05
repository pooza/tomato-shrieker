module TomatoShrieker
  class EntryTestCaseFilter < TestCaseFilter
    def active?
      return Entry.dataset.all.select(&:feed).nil?
    end
  end
end
