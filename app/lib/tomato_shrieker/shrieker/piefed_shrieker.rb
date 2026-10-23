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
      # ⚠ **タグは投稿の前に求める（#1679 の Codex P2）。**モロヘイヤへの問い合わせなどで
      # 落ちるなら、投稿を作る前に落とす＝再実行しても二重にならない。
      tags = tags_of(template)
      response = http.post("/api/#{api_version}/post", {
        body: post_data(template),
        headers: auth_headers,
      })
      attach_tags(response, tags, template.source)
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
    # ⚠⚠ **投稿を作った後なので、例外の種類を選ばずに握る（#1679 の Codex P2）。**
    # `GatewayError` だけだと、応答の形が違うときの `NoMethodError` などがすり抜ける。
    def attach_tags(response, tags, source)
      return if tags.empty?
      id = response.parsed_response.dig('post_view', 'post', 'id')
      raise Ginseng::GatewayError, 'post id not found in response' unless id
      http.put("/api/#{api_version}/post", {
        body: {post_id: id, tags: tags.join(',')},
        headers: auth_headers,
      })
    rescue => e
      logger.warn(
        source: source&.id,
        shrieker: self.class.to_s,
        message: 'tags not attached',
        post_id: id,
        error: Package.error_message(e),
      )
    end

    # テンプレートが本文に並べるのと同じタグを、`#` なしで返す。
    #
    # ⚠ **出どころはテンプレートに合わせて 3 通り。**フィードのエントリは自分のタグ
    # （`Entry#tags`・`title.erb` / `summary.erb`）。本文（`status`）を持つものはソースの
    # タグにリモートのタグ付けを足したもの（`create_tags`・`common.erb`）。予定は本文を
    # 持たないので、ソースのタグだけ（`calendar.erb`）。
    # 🔴 **本文が無いのに `create_tags` を呼ばない（4.15.0 リリース前レビュー）。**リモートの
    # タグ付けが有効だとモロヘイヤへ nil を渡して `NoMethodError` になり、予定 1 件ごとに
    # PieFed 宛が失敗する（4.14.0 では投稿できていた組み合わせ）。
    # ⚠ **`create_tags` を呼ぶのはここの 1 回だけ（#1664 の Codex P2 と同じ理由）。**
    def tags_of(template)
      entry = template.entry
      source = template.source
      tags = entry.tags if entry.respond_to?(:tags)
      tags ||= template[:status] ? source.create_tags(template[:status]) : source.tags
      return tags.map {|v| v.to_s.delete_prefix('#')}.reject(&:empty?).uniq
    end

    # 🔴 **タグは本文にもタイトルにも並べない (#1673)。**編集で付けるので、本文にも
    # 並べると二重に見える。⚠ `[:tag]` は必ず明示する (#1484) — 立てずに描画すると、
    # 同じソースの他の宛先が立てたフラグで結果が変わる。
    # ⚠ 描画は 1 回だけ。URL は消す前に控えておく。
    # ⚠ **タイトルは URL を消した本文から作る (#1671)。**URL を残すと、長さの上限で URL の途中に
    # `…` が入る。URL だけの本文ではタイトルが空になるので、そのときは最初の URL を使う。
    def post_data(template)
      template[:tag] = false
      body = template.to_s
      uris = Ginseng::URI.scan(body).to_a
      # 🔴 **長い URL から消す (#1671)。**短いほうを先に消すと、それを接頭辞に持つ長い URL の
      # 残り（`https://example.com/a` に対する `https://example.com/ab` の `b`）が本文に残る。
      uris.map(&:to_s).uniq.sort_by {|v| -v.length}.each {|v| body.gsub!(v, '')}
      title = body.gsub(/[\r\n[:blank:]]+/, ' ').strip
      title = uris.first.to_s if title.empty?
      title.ellipsize!(TomatoShrieker::Config.instance['/piefed/subject/max_length'])
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
