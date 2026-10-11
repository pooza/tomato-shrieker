module TomatoShrieker
  # 添付（フィードの enclosure ＝ 第三者が書ける URL）を投稿先へ上げる (#1666)。
  #
  # 🔴 **取りにいく先の検証は gem の既定に任せる。**ginseng-fediverse 6.0.0 から
  # `upload_remote_resource` は初段もリダイレクトの各ホップも `Ginseng::PublicHost.validator`
  # を通す（内部ホスト・IP リテラル・解決できない名前は、要求を 1 本も出さずに
  # `GatewayError: Rejected host`）。⚠ ここで自前の検証を足さない＝利用側からは
  # リダイレクト先を検証できず、初段だけの守りが二重に残るだけになる。
  #
  # 🔴 **取れなかった添付は落とし、本文は投稿する。**⚠⚠ 添付の失敗を投稿ごとの失敗に
  # すると、**フィードの書き手が enclosure に 1 本おかしな URL を混ぜるだけで、その
  # エントリが宛先に届かなくなる**（Entry は作成済みなので次の run でも拾われない
  # ＝ #1574）。⚠ 名前解決の一時的な失敗も `Rejected host` で返り、再送されない。
  # ⚠ 投稿先へのアップロードの失敗もここで握るが、宛先が落ちているなら続く投稿が
  # 同じ理由で落ちるので、宛先の不調が緑に化けることはない。
  module RemoteAttachment
    def upload_attachments(attachments, source: nil)
      in_threads = Parallel.processor_count * 2
      ids = Parallel.map(attachments, in_threads:) do |v|
        upload_attachment(v[:image_url], source:)
      end
      return ids.compact
    end

    private

    # ⚠ **ログに出すのはホストまで。**署名付きの画像 URL はクエリに資格情報を持つ。
    # ⚠ `URI::InvalidURIError` は、リダイレクト先の `Location` が読めない形のとき
    # （ginseng-core#695。`GatewayError` にならない）。
    def upload_attachment(url, source: nil)
      return upload_remote_resource(url, {response: :id})
    rescue Ginseng::GatewayError, ::URI::InvalidURIError => e
      logger.warn(
        source: source&.id,
        shrieker: self.class.to_s,
        message: 'attachment dropped',
        host: Ginseng::URI.parse(url.to_s)&.host,
        error: e.message,
      )
      return nil
    end
  end
end
