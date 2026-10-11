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
      template = create_piefed_template(body[:template])
      response = http.post("/api/#{api_version}/post", {
        body: post_data(template),
        headers: auth_headers,
      })
      attach_tags(response, template)
      return response
    end

    private

    def auth_headers
      return {'Authorization' => "Bearer #{@jwt}"}
    end

    # 🔴 **タグは、作成した投稿を編集して付ける (#1673)。**
    #
    # PieFed の投稿の作成（`POST /post`）はタグを受け取らず、本文の `#tag` も拾わない
    # （ただの文字になる。4.14.0 の実投稿で確認）。受け取るのは編集（`PUT /post`）の
    # `tags`（カンマ区切り・`#` なし）だけで、本家の 1.6.0 から変わっていない。
    # ⚠ 編集は `post_id` と `tags` だけを送る。省いた項目は PieFed が既存の値を保つ。
    #
    # 🔴 **タグが付かなくても、投稿は成功として返す。**⚠⚠ ここで例外を上げると
    # `Source#deliver` が「配信に失敗した」と数えるが、**投稿はもう出ている**。
    # 再実行すれば同じ投稿が二重に出る。失敗は warn `tags not attached` で残す。
    def attach_tags(response, template)
      tags = tags_of(template)
      return if tags.empty?
      id = response.parsed_response.dig('post_view', 'post', 'id') rescue nil
      raise Ginseng::GatewayError, 'post id not found in response' unless id
      http.put("/api/#{api_version}/post", {
        body: {post_id: id, tags: tags.join(',')},
        headers: auth_headers,
      })
    rescue Ginseng::GatewayError => e
      logger.warn(
        source: template.source&.id,
        shrieker: self.class.to_s,
        message: 'tags not attached',
        post_id: id,
        error: e.message,
      )
    end

    # テンプレートが本文に並べるのと同じタグを、`#` なしで返す。
    #
    # ⚠ **`create_tags` を呼ぶのはここの 1 回だけ（#1664 の Codex P2 と同じ理由）。**
    # リモートタグ付けが有効ならモロヘイヤへ問い合わせる。⚠ フィードのエントリは自分の
    # タグ（`Entry#tags`）を持つ。それ以外（テキスト・コマンド・予定）はソースのタグ。
    def tags_of(template)
      entry = template.entry
      tags = entry.respond_to?(:tags) ? entry.tags : template.source.create_tags(template[:status])
      return tags.map {|v| v.to_s.delete_prefix('#')}.reject(&:empty?).uniq
    end

    # 🔴 **タグは本文にもタイトルにも並べない (#1673)。**編集で付けるので、本文にも
    # 並べると二重に見える。⚠ `[:tag]` は必ず明示する (#1484) — 立てずに描画すると、
    # 同じソースの他の宛先が立てたフラグで結果が変わる。
    # ⚠ 描画は 1 回だけ。タイトルはその結果の空白を潰した 1 行。URL は消す前に控えておく。
    def post_data(template)
      template[:tag] = false
      body = template.to_s
      title = body.gsub(/[\r\n[:blank:]]+/, ' ')
      title.ellipsize!(TomatoShrieker::Config.instance['/piefed/subject/max_length'])
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
