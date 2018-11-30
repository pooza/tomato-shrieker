module TomatoToot
  class ExternalServiceError < Error
    def status
      return 502
    end
  end
end
