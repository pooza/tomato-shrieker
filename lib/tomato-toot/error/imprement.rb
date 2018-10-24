module TomatoToot
  class ImprementError < ::StandardError
    def status
      return 500
    end
  end
end
