module TomatoShrieker
  class LineTestCaseFilter < TestCaseFilter
    def active?
      @config = Config.instance
      return @config['/line/channels']&.first.nil?
    end
  end
end
