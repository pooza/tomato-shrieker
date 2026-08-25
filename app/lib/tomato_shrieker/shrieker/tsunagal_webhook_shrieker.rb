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
  class TsunagalWebhookShrieker < WebhookShrieker
    # CW と本文を区切る空行。⚠ 1 行にすると CW が本文の一部に見える。
    SEPARATOR = "\n\n".freeze

    def build_body(body)
      result = super
      return result unless (spoiler_text = result.delete(:spoiler_text)).present?
      result[:text] = [spoiler_text, result[:text]].reject(&:blank?).join(SEPARATOR)
      return result
    end
  end
end
