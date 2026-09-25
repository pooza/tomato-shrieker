module TomatoShrieker
  # 1 回の run のあいだの配信試行を集計する。
  # IcalendarSource#exec のように Parallel.each で並列配信するソースがあるため、
  # 更新は全て Mutex で直列化する。
  class DeliveryStats
    attr_reader :attempted_count, :delivered_count, :failure_count

    def initialize
      @mutex = Mutex.new
      @attempted_count = 0
      @delivered_count = 0
      @failure_count = 0
      @shrieker_errors = Hash.new(0)
      @errors = []
      @entry_stage = false
    end

    # 🔴🔴 **エントリ処理段に入った (#1586)。**
    #
    # ⚠⚠ **ここから先で落ちた失敗は、しきい値を緩めてはいけない。**エントリを
    # 読んだ後の失敗はそのぶんのエントリを**恒久的に失う**（FeedSource は
    # `Entry.insert` が配信より先で unique 制約により再取得されない／
    # CommandSource・IcalendarSource は出力が日付に依存して取り返せない）のに、
    # `undelivered?` も `stale` も `silent` も立たないため **`error_streak` が
    # 唯一のゲート**になっている（#1473 / #1558）。
    #
    # ⚠ **取得そのものの失敗（YouTube の 404 等）では呼ばない。**緩和が効いてよい
    # のはそちらだけ。
    # ⚠ **エントリが 0 件なら呼ばない。**失うものが無い run で緩和を潰さない。
    #
    # 🔴 **FeedSource だけは「一覧を取り出した直後」ではない (#1622)。**
    # - `create_record` が**配信対象の行を返した直後**に呼ぶ。一覧は重複判定の前なので、
    #   そこで呼ぶと既知エントリしか無い run（平常時のほぼ全 run）でも段が立つ。
    #   ⚠ insert はしたが意図して流さない行（未 touch / `feed.time` より古い /
    #   `keep_years` の外）は nil が返るので立たない＝失うものが無い
    # - `Entry.create` が `Entry.insert` を**通した後**に落ちたときも呼ぶ。行が残るので
    #   そのエントリは二度と配信されない
    # - ⚠ insert より手前（パース失敗）では呼ばない。行が無いので次の run で読み直す
    def enter_entry_stage!
      @mutex.synchronize {@entry_stage = true}
      return nil
    end

    def entry_stage?
      return @mutex.synchronize {@entry_stage}
    end

    def record_success(shrieker)
      @mutex.synchronize do
        @attempted_count += 1
        @delivered_count += 1
      end
      return nil
    end

    def record_error(shrieker, error)
      return record_attempted_failure(shrieker.class, error)
    end

    # 設定されているのに Shrieker を組み立てられなかった宛先 (#1504)。
    # アクセサが例外を握って nil を返すため、この宛先は shriekers から消える。
    # attempted に載せないと「宛先ゼロで完走した run」＝緑になる。
    def record_unavailable(kind, error)
      return record_attempted_failure(kind, error)
    end

    # 配信まで到達せずに落ちた失敗。Shrieker が特定できない経路（FeedSource#fetch の
    # エントリ単位 rescue 等）から使う。
    #
    # 🔴 attempted_count には載せない。載せると delivered < attempted が成立して
    # undelivered?（#1504）が立つが、これは宛先に一度も触れていない失敗なので
    # 「宛先に届いていない」は嘘になる。しかも undelivered? の解除は
    # 「次に全宛先へ届く run」だけなので、疎なソースは数週間 503 に貼り付く。
    # ⚠ @errors には積むので status は error / partial に倒れる。#1473 が塞いだ
    # 「全エントリが壊れても no-op success になる」穴は error_streak 側で塞がれたまま。
    def record_failure(kind, error)
      @mutex.synchronize do
        @failure_count += 1
        @shrieker_errors[kind.to_s] += 1
        @errors.push(error)
      end
      return nil
    end

    def shrieker_errors
      return @mutex.synchronize {@shrieker_errors.dup}
    end

    # 「宛先に触ったが届かなかった」失敗の共通処理 (#1490)。
    #
    # ⚠⚠ **record_failure と一本化してはいけない。** 見た目は似ているが
    # **`@attempted_count` と `@failure_count` で別の数を数えている**。
    # `record_failure` は宛先に一度も触れていない失敗なので attempted に載せず、
    # 載せると `delivered < attempted` が成立して `undelivered?`（#1504）が嘘で
    # 立つ。⚠ しかも解除は「次に全宛先へ届く run」だけなので、疎なソースは
    # 数週間 503 に貼り付く。
    #
    # ⚠ `kind` は Class でも文字列でもよい（`to_s` で同じ値になる）。
    def record_attempted_failure(kind, error)
      @mutex.synchronize do
        @attempted_count += 1
        @shrieker_errors[kind.to_s] += 1
        @errors.push(error)
      end
      return nil
    end

    def error_count
      return @mutex.synchronize {@errors.size}
    end

    def first_error
      return @mutex.synchronize {@errors.first}
    end

    def error?
      return error_count.positive?
    end

    # 配信を 1 件も試みなかった run。#1457 の「no-op run」の定義。
    # ⚠ 配信手前で落ちた run（failure_count のみ）はここでは no-op に見えるが、
    # @errors が積まれているので status は success にならず、SourceRunLog#noop? は false。
    def noop?
      return attempted_count.zero?
    end
  end
end
