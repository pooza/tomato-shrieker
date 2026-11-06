require 'sequel/model'

module TomatoShrieker
  # 「この沈黙は確認した」という運用者の記録 (#1505)。
  #
  # サイレント不発は**一概に失敗と言えない**（上流が静かなだけのことがある）。
  # しきい値を当てにいくより、いったん赤にして人が判断するほうが確実なので、
  # 確認したら緑に戻せるようにする。
  #
  # ⚠ **「今回は問題なかった」の記録であって「今後も問題ない」の保証ではない。**
  # 起点が前に進むだけなので、そこからさらに silence_tolerance が経過すれば再び赤になる。
  # 「また 1 か月経ったけど、やっぱりおかしくない?」という念押しを残すため。
  #
  # 恒久的に静かなソースは tolerance を設定しない、投稿が終了したソースは
  # disable にする。ack は「一時的に静か」なソースのためのもの。
  class SilenceAck < Sequel::Model(:silence_ack)
    include Package

    def self.acknowledged_at(source_id)
      return where(source_id:).first&.acknowledged_at
    end

    # 確認を記録する。source ごとに 1 行だけ持ち、確認のたびに前に進める。
    #
    # 🔴 **沈黙の起点が動くのは `silence: true` のときだけ (#1680)。**未達や取りこぼしだけを
    # 確認した ack で動かすと、沈黙の警告がそのぶん後ろ倒しになる。⚠ 動かさないときは前の値を
    # 残す（消すと、前に確認した沈黙がまた赤くなる）。
    def self.acknowledge(source_id, at: Time.now, silence: true, run_id: nil, reasons: [])
      values = {
        acknowledged_at: at,
        acknowledged_run_id: run_id,
        acknowledged_reasons: reasons.join(','),
      }
      values[:silence_acknowledged_at] = at if silence
      row = where(source_id:).first
      return row.update(values) if row
      return create(values.merge(source_id:))
    end

    # error の確認を記録する (#1749)。⚠ `acknowledge` の後に呼ぶ（行はそちらが作る）。
    # 🔴 **期限（`until_at`）は確認のたびに置き直す。**期限なしで確認し直したら、前の期限は消える。
    def self.acknowledge_error(source_id, at: Time.now, until_at: nil)
      return where(source_id:).update(error_acknowledged_at: at, error_acknowledged_until: until_at)
    end

    # error の確認を解除する（error で終わらなかった run の後・#1749）。⚠ ほかの確認（沈黙・未達・
    # 取りこぼし）の記録には触らない。
    def self.clear_error(source_id)
      return where(source_id:).exclude(error_acknowledged_at: nil)
          .update(error_acknowledged_at: nil, error_acknowledged_until: nil)
    end

    def reasons
      return acknowledged_reasons.to_s.split(',')
    end
  end
end
