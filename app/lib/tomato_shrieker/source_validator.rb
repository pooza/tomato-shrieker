# frozen_string_literal: true

require 'json-schema'

module TomatoShrieker
  # 単一ソース定義（config/sources/<id>.yaml）を config/schema/source.yaml で検証する。
  class SourceValidator
    include Package

    JSON::Validator.use_multi_json = false

    SCHEMA_FILE = 'config/schema/source.yaml'

    class << self
      def schema
        @schema ||= YAML.load_file(File.join(Environment.dir, SCHEMA_FILE))
      end

      # 検証エラーの配列を返す（空 = 妥当）。params は Hash（YAML ロード済みのソース定義）。
      # json-schema が付与する末尾の「 in schema <uuid>」は可読性のため除去する。
      def validate(params)
        JSON::Validator.fully_validate(schema, params.deep_stringify_keys)
          .map {|message| message.sub(/ in schema [0-9a-f-]+\z/, '')}
      end

      def valid?(params)
        validate(params).empty?
      end

      # スキーマは通るが運用上の穴になる設定の配列を返す（空 = 指摘なし）。
      # errors と違い NG にはしない。silence_tolerance は opt-in なので未指定でも
      # 妥当だが、宣言しなければサイレント不発の検知が丸ごと効かない (#1470)。
      def warnings(params)
        params = params.deep_stringify_keys
        return [] if params['disable'] == true
        return [] if params.dig('schedule', 'at')
        messages = []
        unless params.dig('monitor', 'silence_tolerance')
          messages.push('/monitor/silence_tolerance が未設定です。無配信が続いても検知されません')
        end
        return messages.concat(unreachable_streak_warnings(params))
      end

      private

      # 🔴 **しきい値に到達できない組み合わせを弾く（Codex P1・#1558）。**
      #
      # `error_streak` は `source_run_log` の行を数えるが、その行は
      # `/monitor/retention_days` で prune される。⚠⚠ **実行間隔が疎なソースで
      # しきい値を上げると、必要な本数の error 行が揃う前に古い行が消える**ため、
      # **どれだけ連続で失敗しても 503 にならない**。
      #
      # 例: 月次 cron のソースにしきい値 3 を置くと、retention 14 日では
      # 保護行＋直近の error しか残らず、永久に 2 未満のまま。⚠ `stale` も
      # 助けにならない（run 自体は走っていて `executed_at` は前に進む）。
      #
      # ⚠ **NG ではなく WARN にする。**妥当な設定（15 分間隔 × 8 = 2 時間）と
      # 見分けるのに実行間隔が要り、それはスキーマでは表現できない。
      def unreachable_streak_warnings(params)
        threshold = params.dig('monitor', 'error_streak_threshold')
        return [] unless threshold.is_a?(Numeric) && threshold.to_i > 1
        return [] unless seconds = schedule_interval_seconds(params)
        days = (threshold.to_i * seconds / 86_400.0).ceil
        retention = Config.instance['/monitor/retention_days']
        return [] if days <= retention
        return [
          "/monitor/error_streak_threshold (#{threshold.to_i}) に到達するには約 #{days} 日ぶんの" \
            " run が必要ですが、/monitor/retention_days は #{retention} 日です。" \
            'prune で先に消えるため、連続して失敗しても 503 になりません',
        ]
      end

      # 2 回続けて発火する間隔。⚠ **`at` のソースはここへ来ない**（呼び出し側で除外済み）。
      #
      # ⚠ 壊れた cron / period は nil を返す。**警告を出す処理が例外で倒れて
      # `source validate` 全体を止めるほうが害が大きい**し、書式そのものの誤りは
      # スキーマと起動時の register が別に捕まえる。
      def schedule_interval_seconds(params)
        schedule = params['schedule']
        return nil unless schedule
        if (cron = schedule['cron'])
          first = Rufus::Scheduler.parse(cron).next_time(Time.now).to_t
          return Rufus::Scheduler.parse(cron).next_time(first).to_t - first
        end
        return Rufus::Scheduler.parse(schedule['every']).to_i if schedule['every']
        return nil
      rescue StandardError
        return nil
      end
    end
  end
end
