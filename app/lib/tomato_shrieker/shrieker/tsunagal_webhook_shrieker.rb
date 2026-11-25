module TomatoShrieker
  # [tsunagal/matrix-webhook](https://github.com/tsunagal/matrix-webhook) 宛の
  # Shrieker (#1493)。
  #
  # ⚠⚠ **クラス名が `Matrix～` でないのは意図的。** 喋る相手は Matrix の
  # Client-Server API ではなく **`tsunagal/matrix-webhook` という HTTP webhook**
  # なので、`MatrixShrieker` は将来 C-S API を実装するときのために空けてある。
  #
  # 🔴 **matrix-webhook は `text` / `channel` / `room_id` / `format` しか見ない。**
  # 未知のフィールドは黙って無視されるので、`WebhookShrieker` が積む
  # `spoiler_text` は **エラーにもならずに落ちていた**。同じソースをモロヘイヤと
  # matrix-webhook の両方へ流すと、Matrix 宛だけ CW の内容が消える。
  #
  # ⚠ **Matrix に CW の標準は無い。** 独自の見せ方を決めることになるので、
  # 「本文の先頭に畳んで送る」という最小の解釈にしてある。
  #
  # 🔴 **エントリーのある投稿は `title` を送る (#1825)。**matrix-webhook は POST ごとに
  # スレッドを起こし、`title` が無ければ `text` の最初の行をルートにする。
  # `summary_with_title` などのテンプレートは 1 行目が `[prefix]` だけなので、
  # **同じソースのスレッドが同じタイトルで並んで見分けが付かなかった**。
  # ⚠ エントリーの無いソース（定型文・コマンド）は従来どおり本文の 1 行目に任せる。
  class TsunagalWebhookShrieker < WebhookShrieker
    # CW と本文を区切る空行。⚠ 1 行にすると CW が本文の一部に見える。
    SEPARATOR = "\n\n".freeze

    def build_body(body)
      template = body[:template]
      result = super
      if (spoiler_text = result.delete(:spoiler_text)).present?
        result[:text] = [spoiler_text, result[:text]].reject(&:blank?).join(SEPARATOR)
      end
      if title = thread_title(template)
        result[:title] = title
      end
      return result
    end

    # `[prefix] エントリーの題`。⚠ 長さは matrix-webhook が 60 文字で切るので、ここでは切らない。
    def thread_title(template)
      return nil unless title = entry_title(template.entry).presence
      prefix = template.source&.prefix.presence
      return [prefix && "[#{prefix}]", title].compact.join(' ')
    end

    private

    # 🔴 **エントリーの形はソースで違う（#1826 の Codex P2）。**フィードは `Entry` のオブジェクトだが、
    # `IcalendarSource` は `create_entry` の Hash（`Template#[]=` が鍵をシンボルにする）を入れる。
    # ⚠ `entry&.title` だけだと、予定のソースを Tsunagal へ向けた途端に NoMethodError で投稿が落ちる。
    def entry_title(entry)
      return entry[:title] if entry.is_a?(Hash)
      return entry&.title
    end
  end
end
