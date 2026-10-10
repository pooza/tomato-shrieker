module TomatoShrieker
  class PiefedShrieker < Ginseng::Piefed::Service
    include Package

    def initialize(params = {})
      params = params.deep_symbolize_keys
      params[:url] = "https://#{params[:host]}" if params[:host] && !params[:url]
      params[:user] = params[:user_id] if params[:user_id] && !params[:user]
      super
    end

    def api_version
      return @params[:api_version] || super
    end

    def exec(body)
      # ⚠ **構築時ではなくここで login する (#1514)。**上流の `Service#login` は
      # `return if @jwt` を持つので、二重に叩くことはない。構築時に無条件で叩くと、
      # 投稿しないケース（設定の読み込み・`source list`・テストの初期化）でも
      # PieFed の認証 API を叩き、レートリミット (429) を踏みやすくなる。
      login
      data = post_data(create_piefed_template(body[:template]))
      return http.post("/api/#{api_version}/post", {
        body: data,
        headers: {'Authorization' => "Bearer #{@jwt}"},
      })
    end

    private

    # 🔴 **タグは本文にだけ付け、タイトルには付けない。どちらも明示する (#1484)。**
    #
    # 以前は `[:tag]` を立てずに描画していたので、同じソースに他の宛先があると、その並び順で
    # タグが付いたり落ちたりしていた（単独なら付かない・Mastodon / Misskey と併用なら付く）。
    # ⚠ タイトルは描画結果の空白を潰した 1 行なので、同じ描画を使うとタイトルにタグが並ぶ。
    def post_data(template)
      template[:tag] = false
      title = template.to_s.gsub(/[\r\n[:blank:]]+/, ' ')
      title.ellipsize!(TomatoShrieker::Config.instance['/piefed/subject/max_length'])
      template[:tag] = true
      # ⚠ **本文の描画は 1 回だけ（#1664 の Codex P2）。**タグ付きの描画は `create_tags` を通り、
      # リモートタグ付けが有効ならモロヘイヤへ問い合わせる。URL は消す前に控えておく。
      body = template.to_s
      uris = Ginseng::URI.scan(body).to_a
      uris.each {|uri| body.gsub!(uri.to_s, '')}
      data = {title:, body:, community_id: template.source['/dest/piefed/community_id']}
      uri = (template.entry || template.source).uri rescue uris.first
      data[:url] = uri.to_s if uri
      return data
    end

    def create_piefed_template(original)
      source = original.source
      piefed_template_name = source['/dest/piefed/template']
      return original unless piefed_template_name

      template = Template.new(piefed_template_name)
      template[:source] = source
      template[:entry] = original.entry
      template[:status] = original[:status]
      return template
    end
  end
end
