require 'sequel/model'

module TomatoShrieker
  class SourceRunLog < Sequel::Model(:source_run_log)
    include Package

    STATUS_SUCCESS = 'success'.freeze
    STATUS_ERROR = 'error'.freeze

    dataset_module do
      def latest_for(source_id)
        return where(source_id:).order(Sequel.desc(:executed_at)).first
      end

      def recent_for(source_id, limit)
        return where(source_id:).order(Sequel.desc(:executed_at), Sequel.desc(:id)).limit(limit).all
      end
    end

    def error?
      return status == STATUS_ERROR
    end

    # 配信を 1 件も試みずに完走した run。#1457 の「no-op run」。
    # run 自体が失敗した場合は試行ゼロでも no-op ではない。
    def noop?
      return false if error?
      return attempted_count.to_i.zero?
    end

    def delivered?
      return delivered_count.to_i.positive?
    end

    def shrieker_error_counts
      return {} if shrieker_errors.blank?
      parsed = JSON.parse(shrieker_errors)
      return parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      return {}
    end

    def self.record_success(source_id, started_at:, stats: nil)
      create({
        source_id:,
        executed_at: started_at,
        status: STATUS_SUCCESS,
        duration_ms: duration_ms(started_at),
      }.merge(stats_columns(stats)))
    rescue => e
      Sentry.capture_exception(e) if Sentry.initialized?
    end

    def self.record_error(source_id, started_at:, error:, stats: nil)
      create({
        source_id:,
        executed_at: started_at,
        status: STATUS_ERROR,
        error_message: "#{error.class}: #{error.message}",
        duration_ms: duration_ms(started_at),
      }.merge(stats_columns(stats)))
    rescue => e
      Sentry.capture_exception(e) if Sentry.initialized?
    end

    def self.stats_columns(stats)
      return {} unless stats
      errors = stats.shrieker_errors
      return {
        attempted_count: stats.attempted_count,
        delivered_count: stats.delivered_count,
        shrieker_errors: errors.empty? ? nil : JSON.dump(errors),
      }
    end

    def self.prune(retention_days)
      cutoff = Time.now - (retention_days * 86_400)
      return where(Sequel.lit('executed_at < ?', cutoff)).exclude(id: last_delivered_ids).delete
    end

    # 「最後に配信できた時刻」の根拠行はソースごとに 1 行だけ prune から守る。
    # 刈ってしまうと沈黙が retention_days を超えた瞬間に last_delivered_at が nil に化け、
    # 長期の沈黙ほど検知できなくなる (#1470)。
    def self.last_delivered_ids
      return where(Sequel.lit('delivered_count > 0')).group(:source_id)
          .select(Sequel.function(:max, :id))
    end

    def self.duration_ms(started_at)
      return ((Time.now - started_at) * 1000).to_i
    end

    # 実際に配信できた最後の時刻。run_log は retention_days で刈られるため、
    # ここが nil でも「一度も配信していない」とは限らない (#1470)。
    def self.last_delivered_at(source_id)
      row = where(source_id:).where(Sequel.lit('delivered_count > 0'))
        .order(Sequel.desc(:executed_at)).first
      return row&.executed_at
    end

    # 直近 N 件から求まる指標をまとめて返す。
    # /status.json は全ソース分を 1 リクエストで返すので、
    # 指標ごとに recent_for を呼ぶとソース数 × 指標数のクエリになる。ここで 1 回に畳む。
    def self.summary_for(source_id, limit: streak_window)
      logs = recent_for(source_id, limit)
      return {
        error_streak: error_streak_of(logs),
        noop_streak: noop_streak_of(logs),
        duration_ms: duration_stats_of(logs),
        shrieker_errors: shrieker_error_distribution_of(logs),
      }
    end

    # 連続エラー回数 (#1457)。
    #
    # no-op run (新着が無く配信ゼロで完走した run) は「エラーでない」＝ run が最後まで
    # 走った証拠なので streak を切る。ここを読み飛ばすと、配信のたびにしか streak が
    # 戻らなくなり、新着の少ないソースが一過性エラー 1 回で 503 に貼り付く。
    # 「単発で倒さない」は error_streak_threshold で調整する。
    def self.error_streak(source_id, limit: streak_window)
      return error_streak_of(recent_for(source_id, limit))
    end

    def self.error_streak_of(logs)
      streak = 0
      logs.each do |log|
        break unless log.error?
        streak += 1
      end
      return streak
    end

    # 何も配信しないまま連続した run の回数 (#1470)。
    # エラーで終わった run も「配信できていない」ので数に入れる。
    def self.noop_streak(source_id, limit: sample_size)
      return noop_streak_of(recent_for(source_id, limit))
    end

    def self.noop_streak_of(logs)
      streak = 0
      logs.each do |log|
        break if log.delivered?
        streak += 1
      end
      return streak
    end

    def self.duration_stats(source_id, limit: sample_size)
      return duration_stats_of(recent_for(source_id, limit))
    end

    def self.duration_stats_of(logs)
      values = logs.filter_map(&:duration_ms).sort
      return nil if values.empty?
      return {
        min: values.first,
        avg: (values.sum.to_f / values.size).round,
        max: values.last,
        p95: values[percentile_index(values.size, 95)],
      }
    end

    def self.percentile_index(size, percentile)
      index = ((size * percentile) / 100.0).ceil - 1
      return index.clamp(0, size - 1)
    end

    def self.error_rate(source_id, hours: 24)
      since = Time.now - (hours * 3600)
      logs = where(source_id:).where(Sequel.lit('executed_at >= ?', since)).all
      return nil if logs.empty?
      return (logs.count(&:error?).to_f / logs.size).round(3)
    end

    # 直近 N 件の shrieker 別エラー件数 (#1433)。
    def self.shrieker_error_distribution(source_id, limit: sample_size)
      return shrieker_error_distribution_of(recent_for(source_id, limit))
    end

    def self.shrieker_error_distribution_of(logs)
      distribution = Hash.new(0)
      logs.each do |log|
        log.shrieker_error_counts.each {|klass, count| distribution[klass] += count.to_i}
      end
      return distribution
    end

    def self.sample_size
      return Config.instance['/monitor/sample_size']
    end

    # error_streak_threshold が sample_size より大きいと、読む行数が足りず
    # しきい値に到達し得ない＝どれだけ連続で失敗しても健全のままになる。
    def self.streak_window
      return [sample_size, Config.instance['/monitor/error_streak_threshold']].max
    end
  end
end
