module TomatoShrieker
  class LineShrieker < Ginseng::LineService
    include Package

    def initialize(params = {})
      super rescue nil
      @id = params[:id]
      @token = params[:token]
    end

    def exec(body)
      body = body.clone
      body[:template][:tag] = false
      return say(body[:template].to_s.strip)
    end
  end
end
