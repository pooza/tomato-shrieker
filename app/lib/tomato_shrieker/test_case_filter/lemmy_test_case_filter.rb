module TomatoShrieker
  class LemmyTestCaseFilter < TestCaseFilter
    def active?
      @config = Config.instance
      return @config['/lemmy/services']&.first.nil?
    end
  end
end
