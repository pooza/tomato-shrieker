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
    def self.acknowledge(source_id, at: Time.now)
      row = where(source_id:).first
      return row.update(acknowledged_at: at) if row
      return create(source_id:, acknowledged_at: at)
    end
  end
end
