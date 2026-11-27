module TomatoShrieker
  class HTTP < Ginseng::HTTP
    include Package

    # 取得元が間欠的に 404 を返すとき true にする (#1500)。
    #
    # ⚠ **既定は false のまま。**ginseng-core の「恒久的な失敗を再送しない」方針
    # (RETRYABLE_STATUSES = [408, 425, 429]) は正しく、全体を巻き戻してはいけない。
    # webhook の POST が返す 404 は宛先設定の誤りで、再送しても結果は変わらない。
    # 実際 synapse.b-shock.org/webhook が 404 を返し続けた前例がある (#1455)。
    attr_accessor :retry_not_found

    # 運用者が設定した URL（フィード・iCalendar）を GET する (#1688)。
    #
    # 🔴 **初段のホストは検証しない。**運用者の設定なので信頼でき、LAN 内の正規の取得元
    # （google-news-rss-cleaner の `scylla.b-shock.local:3000` など）を含む。一律に
    # `Ginseng::PublicHost.validator` を挿すと、それらが落ちる。
    # 🔴 **別のホストへのリダイレクト先だけを `PublicHost` で検証する。**配信元（第三者）が
    # 3xx で内部ホストを指すと、検証なしでは内部への GET を踏まされる（blind SSRF・#1666 の同族）。
    # ⚠ 初段と同じ扱いで通すのは、**同じホスト・同じポートで、scheme が同じか http → https に
    # 上がるもの**だけ（パスの移動・https 化）。別のポート・https → http は別のホストと同じく
    # `PublicHost` に掛ける（#1800。ginseng-core 7.1.0 から validator がホップの URI を受け取れる）。
    # 2026-11-07 の本番の実測では、初段で 3xx を返すのは 2 件で、どちらも同じホストだった。
    def get_configured(uri, options = {})
      uri = create_uri(uri)
      return get(uri, {max_bytes: self.class.max_bytes}.merge(options)
        .merge(host_validator: self.class.configured_host_validator(uri)))
    end

    # 取りにいく本文の上限（`/http/max_bytes`・#1781）。超えたら読むのをやめて `Ginseng::TooLargeError`
    # （`GatewayError` の下位）を上げる＝その run は取得段の失敗になる。
    # 🔴 **パーサに渡す前に止める。**改行の無い 50MB を読ませると、パーサが RSS 4GB・9 秒を使った
    # （4.16.0 リリース前レビューの実測）。⚠ ginseng-core 7.1.1 より前は、`max_bytes:` を付けた応答の
    # `to_s` が本文を返さなかった（`Icalendar::Calendar.parse` は応答をそのまま渡す）。
    def self.max_bytes
      return config['/http/max_bytes']
    end

    # 初段と同じ口は通し、それ以外は `PublicHost` の判定（接続先の IP アドレスか nil）を返す。
    # ⚠ `uri:` を宣言しているので、ginseng-core はホップの URI を渡す。⚠ URI はクエリや
    # userinfo を含みうるので、ここでログに出さない。
    def self.configured_host_validator(origin, public_host: Ginseng::PublicHost.validator)
      origin = Ginseng::URI.parse(origin.to_s)
      return lambda do |host, uri:|
        return true if same_origin?(origin, Ginseng::URI.parse(uri.to_s))
        return public_host.call(host)
      end
    end

    def self.same_origin?(origin, target)
      return false unless target.normalized_host == origin.normalized_host
      return true if upgrade?(origin, target)
      return false unless target.normalized_scheme == origin.normalized_scheme
      return target.inferred_port == origin.inferred_port
    end

    # http（既定のポート）→ https（既定のポート）への引き上げ。
    def self.upgrade?(origin, target)
      return false unless origin.normalized_scheme == 'http' && origin.inferred_port == 80
      return target.normalized_scheme == 'https' && target.inferred_port == 443
    end

    private

    # YouTube の /feeds/videos.xml は、チャンネルが生きていても間欠的に 404 を返す
    # (#1500 で 5 チャンネルぶん実測)。404 を恒久的な失敗として即 raise すると、
    # 一過性の揺らぎがそのまま run の失敗になり、監視が赤に貼り付く。
    # ginseng-upstream: no — 404 を再送するのは YouTube の /feeds/videos.xml の事情（一般には恒久的な失敗）。
    def retryable?(error)
      return true if retry_not_found && not_found?(error)
      return super
    end

    def not_found?(error)
      return false unless error.is_a?(Ginseng::GatewayError)
      return error.source_status == 404
    end
  end
end
