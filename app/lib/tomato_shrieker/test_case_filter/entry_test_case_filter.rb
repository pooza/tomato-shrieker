module TomatoShrieker
  class EntryTestCaseFilter < TestCaseFilter
    def active?
      return Entry.dataset.empty?
    end
  end
end
