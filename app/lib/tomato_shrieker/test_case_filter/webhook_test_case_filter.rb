module TomatoShrieker
  class WebhookTestCaseFilter < TestCaseFilter
    def active?
      return Source.all.none? {|s| s.test? && s.webhook?}
    end
  end
end
