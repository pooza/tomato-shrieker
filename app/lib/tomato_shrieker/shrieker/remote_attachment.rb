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
  # ⚠ 投稿先へのアップロードの失敗もここで握る。宛先ごと落ちているなら続く投稿が同じ
  # 理由で落ちるが、**メディアの API だけが通らない形（権限・サイズ上限）は、画像なしの
  # 投稿が成功として続く**＝監視には出ず、warn `attachment dropped` でしか分からない。
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
        error: dropped_reason(e),
      )
      return nil
    end

    # 🔴 **`InvalidURIError` はクラス名だけを出す（4.15.0 リリース前レビュー）。**メッセージは
    # `bad URI (is not URI?): "<Location 全体>"` で、**読めない URL はログのマスクが素通しに
    # する**ので、リダイレクト先の署名がそのまま残る（実測）。ほかは `Package.error_message`
    # を通す（docs/CLAUDE.md。クラス名が付き、文字コードとマスクも通る）。
    def dropped_reason(error)
      return error.class.to_s if error.is_a?(::URI::InvalidURIError)
      return Package.error_message(error)
    end
  end
end
