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
    # ⚠ 同じホストへのリダイレクト（http → https・パスの移動）は初段と同じ扱いで通す。
    # 2026-11-07 の本番の実測では、初段で 3xx を返すのは 2 件で、どちらも同じホストだった。
    def get_configured(uri, options = {})
      uri = create_uri(uri)
      return get(uri, options.merge(host_validator: self.class.configured_host_validator(uri.host)))
    end

    # 初段のホストは通し、それ以外は `PublicHost` の判定（接続先の IP アドレスか nil）を返す。
    def self.configured_host_validator(origin_host, public_host: Ginseng::PublicHost.validator)
      origin_host = origin_host.to_s.downcase
      return lambda do |host|
        return true if host.to_s.downcase == origin_host
        return public_host.call(host)
      end
    end

    private

    # YouTube の /feeds/videos.xml は、チャンネルが生きていても間欠的に 404 を返す
    # (#1500 で 5 チャンネルぶん実測)。404 を恒久的な失敗として即 raise すると、
    # 一過性の揺らぎがそのまま run の失敗になり、監視が赤に貼り付く。
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
