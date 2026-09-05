module TomatoShrieker
  class LineShrieker < Ginseng::LineService
    include Package

    def initialize(params = {})
      # 親の初期化は config が無い環境でも落とさない。ただし黙って捨てると
      # 後段の say 失敗の原因が追えなくなるので記録は残す (#1473)。
      #
      # ⚠ **ここで落とさないのは意図的。**組み立てに失敗すると `shriekers` から
      # この宛先が消え、「設定はあるのに宛先ゼロ」になって #1504 の計上が崩れる。
      begin
        super
      rescue => e
        # 🔴 **失敗を持ち越す (#1487)。**握ったまま続行すると `@http.base_uri` が
        # 未設定のまま残り、後段の `say` が
        # `NoMethodError: undefined method 'prefix' for nil` で落ちる。
        # ⚠⚠ **run_log と `/healthz` に出るのは真因の `Ginseng::ConfigError` ではなく
        # 症状の `NoMethodError`** になり、運用者は原因にたどり着けない。
        @init_error = e
        logger.error(shrieker: self.class.to_s, error: e, message: 'initialization failed')
      end
      @id = params[:id]
      @token = params[:token]
    end

    def exec(body)
      # ⚠ **投げ直すのは exec の冒頭。**`Source#shriek` の rescue が `source: id` 付きで
      # 記録するので、真因がそのまま run_log → `/healthz` まで届く。
      # ⚠ 初期化時のログにソース ID は入らない（LineShrieker は自分の source を
      # 知らない）。**本番の LINE ソースは 2 件あるので、ログだけでは判別できない。**
      raise @init_error if @init_error
      body = body.clone
      body[:template][:tag] = false
      return say(body[:template].to_s.strip)
    end
  end
end
