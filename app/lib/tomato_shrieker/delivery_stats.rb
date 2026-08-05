module TomatoShrieker
  # 1 回の run のあいだの配信試行を集計する。
  # IcalendarSource#exec のように Parallel.each で並列配信するソースがあるため、
  # 更新は全て Mutex で直列化する。
  class DeliveryStats
    attr_reader :attempted_count, :delivered_count

    def initialize
      @mutex = Mutex.new
      @attempted_count = 0
      @delivered_count = 0
      @shrieker_errors = Hash.new(0)
      @errors = []
    end

    def record_success(shrieker)
      @mutex.synchronize do
        @attempted_count += 1
        @delivered_count += 1
      end
      return nil
    end

    def record_error(shrieker, error)
      @mutex.synchronize do
        @attempted_count += 1
        @shrieker_errors[shrieker.class.to_s] += 1
        @errors.push(error)
      end
      return nil
    end

    # 配信まで到達せずに落ちた失敗。Shrieker が特定できない経路（FeedSource#fetch の
    # エントリ単位 rescue 等）から使う。これを計上しないと、全エントリが壊れていても
    # attempted=0 の no-op success になり error_streak にも error_rate にも出ない (#1473)。
    def record_failure(kind, error)
      @mutex.synchronize do
        @attempted_count += 1
        @shrieker_errors[kind.to_s] += 1
        @errors.push(error)
      end
      return nil
    end

    def shrieker_errors
      return @mutex.synchronize {@shrieker_errors.dup}
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
    def noop?
      return attempted_count.zero?
    end
  end
end
