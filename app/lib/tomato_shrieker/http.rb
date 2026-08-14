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
