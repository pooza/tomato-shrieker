module TomatoShrieker
  class LineShrieker < Ginseng::LineService
    include Package

    def initialize(params = {})
      # 親の初期化は config が無い環境でも落とさない。ただし黙って捨てると
      # 後段の say 失敗の原因が追えなくなるので記録は残す (#1473)。
      begin
        super
      rescue => e
        logger.error(shrieker: self.class.to_s, error: e, message: 'initialization failed')
      end
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
