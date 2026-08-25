module TomatoShrieker
  class WebhookShrieker < SlackService
    include Package

    # `/dest/hooks` の `type` と Shrieker の対応。
    # ⚠ **クラスそのものではなく名前で持つ。** 定数の初期化はこのファイルの
    # 読み込み時に走るので、クラスを直に書くと子クラスがまだ未定義で NameError
    # になる（Zeitwerk の遅延ロードに任せる）。
    CLASSES = {
      'tsunagal' => 'TomatoShrieker::TsunagalWebhookShrieker',
    }.freeze

    # `/dest/hooks` の 1 要素から Shrieker を作る (#1493)。
    #
    # ⚠⚠ **`self.new` を差し替えてファクトリにしない。** 子クラスが継承した
    # `new` から自分自身を作りに行き、無限再帰になる。呼び出し側は `create` を使う。
    #
    # ⚠ **種別は `type` キーの明示だけで決める。** `room_id` の有無のような
    # 暗黙判定に頼らない。`channel` は Slack でも意味を持つので使えず、
    # 「Matrix 固有なのは `room_id` だけ」という前提に乗ると、`channel` だけで
    # 書かれた Tsunagal 宛（本番の 3 ソースがこの形）を取りこぼす。
    def self.create(hook)
      return new(hook) unless hook.is_a?(Hash)
      name = CLASSES[hook.deep_symbolize_keys[:type].to_s]
      return (name ? name.constantize : self).new(hook)
    end

    def initialize(hook)
      case hook
      when Ginseng::URI
        super
      when String
        super(Ginseng::URI.parse(hook))
      when Hash
        hook = hook.deep_symbolize_keys
        super(hook[:url])
        @params = hook
      end
    end

    def exec(body)
      return post(body)
    end

    def channel
      return @params[:channel] rescue nil # matrix-webhook で使用
    end

    def room_id
      return @params[:room_id] rescue nil # matrix-webhook で使用
    end

    def post(body, type = :hash)
      return @http.post(@uri, {body: create_body(body)})
    end

    def create_body(body, type = :hash)
      return build_body(body).to_json
    end

    # 送信する payload を Hash で組み立てる。⚠ **宛先ごとの差は `create_body`
    # ではなくここを override して出す (#1493)。** `create_body` を丸ごと
    # 差し替えると、下の `body[:template][:tag] = true` を落としやすい
    # （#1484 が前提にしている）。
    def build_body(body)
      body = body.clone
      body[:template][:tag] = true
      body[:text] = body[:template].to_s.strip
      if spoiler_text = body[:template].source.spoiler_text
        body[:spoiler_text] = spoiler_text
      end
      body[:channel] ||= channel if channel
      body[:room_id] ||= room_id if room_id
      body.delete(:template)
      return body
    end
  end
end
