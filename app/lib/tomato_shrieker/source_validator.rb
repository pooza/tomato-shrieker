# frozen_string_literal: true

require 'json-schema'

module TomatoShrieker
  # 単一ソース定義（config/sources/<id>.yaml）を config/schema/source.yaml で検証する。
  class SourceValidator
    include Package

    JSON::Validator.use_multi_json = false

    SCHEMA_FILE = 'config/schema/source.yaml'

    # `Source#register` が rufus へ渡すキーと、起動時に実際に通るパーサの対応 (#1570)。
    # ⚠ **総称の `Rufus::Scheduler.parse` を使ってはいけない。**cron 文字列を渡しても
    # `Fugit::Cron` として通ってしまうので、`every: '0 0 * * *'` のような**キーと値の
    # 取り違えを見逃す**。`register` と同じ分岐・同じパーサで引くこと。
    SCHEDULE_PARSERS = {'at' => :parse_at, 'cron' => :parse_cron, 'every' => :parse_duration}.freeze

    # ⚠ `IcalendarSource#remind_minutes` の既定と同じ値。ずれると「省略時は倒れないのに
    # 明示すると倒れる」（またはその逆）になる。
    DEFAULT_REMIND_MINUTES = 5

    class << self
      def schema
        @schema ||= YAML.load_file(File.join(Environment.dir, SCHEMA_FILE))
      end

      # 検証エラーの配列を返す（空 = 妥当）。params は Hash（YAML ロード済みのソース定義）。
      # json-schema が付与する末尾の「 in schema <uuid>」は可読性のため除去する。
      def validate(params)
        params = params.deep_stringify_keys
        errors = JSON::Validator.fully_validate(schema, params)
          .map {|message| message.sub(/ in schema [0-9a-f-]+\z/, '')}
        return errors.concat(schedule_errors(params))
      end

      # 🔴 **起動なら倒れる schedule を、起動と同じパーサで先に弾く (#1570)。**
      #
      # `config/schema/source.yaml` の `cron` / `every` / `at` は `type: string` しか
      # 見ていないので、**スキーマだけでは書き間違いを通す**。2026-09-05 には
      # `cron: '17,47 * * * *'` の `*` が**シェルの glob でリポジトリ直下のファイル一覧
      # （338 文字）へ展開された**状態で YAML に入り、`register_all` が倒れて
      # **7 回の再起動・約 50 秒 全ソース停止**した。
      #
      # ⚠ **完全な cron 正規表現は書けない**ので、スキーマの `pattern` では解けない。
      # `Source#register` が渡す先と同じ `Rufus::Scheduler` のパーサを直接呼ぶ。
      #
      # ⚠⚠ **`disable: true` は検査しない。**`Scheduler#desired_sources` が弾くので
      # rufus まで届かない＝**起動は倒れない**。🔴 **「直せないなら止めれば通る」は
      # `source reload` の拒否 (#1570) の唯一の逃げ道**なので、ここを厳しくすると
      # 逃げ道ごと塞ぐことになる。
      def schedule_errors(params)
        params = params.deep_stringify_keys
        return [] if params['disable'] == true
        schedule = params['schedule']
        return [] unless schedule.is_a?(Hash)
        errors = [main_schedule_error(schedule)]
        errors.push(remind_error(schedule)) if remind_scheduled?(params)
        return errors.compact
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

      # ⚠⚠ **`Source#register` の優先順（`at` > `cron` > `every`）に合わせて、
      # 実際に使われる 1 本だけを見る（#1570 の Codex P2）。**スキーマは複数キーを
      # 許すので、`{at: <妥当>, cron: 'not a cron'}` は **`at` で問題なく起動する**。
      # 🔴 全部を見ると**「起動はできるのに reload は拒否される」**＝ #1570 が直した
      # 食い違いを、向きだけ変えて自分で作ることになる。
      def main_schedule_error(schedule)
        key, parser = SCHEDULE_PARSERS.find {|k, _| schedule[k]}
        return nil unless key
        return schedule_error(schedule[key], key, parser)
      end

      # 🔴 **remind は本体のスケジュールと別に立つ（#1570 の Codex P1）。**
      # `IcalendarSource#register` は `schedule_remind` を**本体より先に**呼び、
      # `"#{minutes}m"` を `scheduler.every` へ渡す。⚠⚠ `minutes: 0` は
      # `parse_duration` では通る（0 を返すだけ）が、`every` が
      # `cannot schedule ... with a frequency of 0` で倒れる＝**起動が落ちる**。
      def remind_error(schedule)
        minutes = schedule.dig('remind', 'minutes') || DEFAULT_REMIND_MINUTES
        return nil unless minutes.is_a?(Numeric)
        return nil if minutes.positive?
        return '/schedule/remind/minutes: cannot schedule with a frequency of' \
          " #{minutes} (#{minutes}m)"
      end

      # ⚠ **remind ジョブを立てるクラスにマッチする定義だけを見る。**`schedule.remind` は
      # スキーマ上どのソースにも書けるが、**立てるのは `IcalendarSource` だけ**。
      # 他のソースでは無視される設定なので、ここで NG にすると上と同じ食い違いになる。
      def remind_scheduled?(params)
        return false unless params.dig('schedule', 'remind', 'enable') == true
        return matched_classes(params).any? {|klass| klass.method_defined?(:remind)}
      end

      # `Source.all` と同じ選び方。⚠ **判別キーは `/source/classes` が正本**なので、
      # クラス名をここへ書き写さない。
      def matched_classes(params)
        flat = params.key_flatten
        return Source.classes.select {|entry| flat[entry[:config]]}.map {|entry| entry[:class]}
      end

      # 🔴 **実体を作って `cron` / `period` を聞く (#1587)。**⚠⚠ params を直接読むと
      # **`schedule` を省いた定義の既定（`Source#default_period` = `5m` /
      # `IcalendarSource#default_cron` = `0 0 * * *`）を見落とす**。`register` が使うのと
      # 同じアクセサを通せば、既定も優先順（`at` > `cron` > `every`）もそのまま効く。
      def matched_sources(params)
        return matched_classes(params).map {|klass| klass.new(params)}
      end

      # ⚠ **型違いはスキーマの担当。**ここで拾うと、同じ 1 つの誤りが
      # 「type が string でない」と「パースできない」の 2 通りで出る。
      def schedule_error(value, key, parser)
        return nil unless value.is_a?(String)
        Rufus::Scheduler.public_send(parser, value)
        return nil
      rescue StandardError => e
        return "/schedule/#{key}: #{e.message}"
      end

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
        threshold = threshold.to_i
        retention = Config.instance['/monitor/retention_days']
        runs = runs_within_retention(params, retention, threshold)
        return [] if runs.nil? || runs >= threshold
        return [
          "/monitor/error_streak_threshold (#{threshold}) に到達するには run が #{threshold} 回" \
            " 必要ですが、/monitor/retention_days (#{retention} 日) の間に発火するのは" \
            " #{runs} 回だけです。prune で先に消えるため、連続して失敗しても 503 になりません",
        ]
      end

      # retention の窓に何回発火するか。⚠ `threshold` に届いた時点で打ち切る
      # （`* * * * *` に大きなしきい値を置かれても走査が伸びない）。
      #
      # 🔴 **回数を実際に数える（Codex P2・#1587）。**⚠⚠ 以前は「次の 2 回の間隔」を
      # 全体へ引き伸ばしていたので、**平日限定 cron のような不均一な指定で所要日数を
      # 過小評価した**。しかも **`source validate` を叩いた曜日で結果が変わる**
      # （月曜なら 1 日刻み、金曜なら 3 日刻み）。
      #
      # ⚠ 壊れた cron / period は nil を返す。**警告を出す処理が例外で倒れて
      # `source validate` 全体を止めるほうが害が大きい**し、書式そのものの誤りは
      # `schedule_errors` と起動時の register が別に捕まえる。
      def runs_within_retention(params, retention, limit)
        return nil unless source = matched_sources(params).first
        return nil if source.post_at
        deadline = Time.now + (retention * 86_400)
        return count_cron_runs(source.cron, deadline, limit) if source.cron
        return nil unless period = source.period
        return nil unless (seconds = Rufus::Scheduler.parse_duration(period)).positive?
        return [((deadline - Time.now) / seconds).floor, limit].min
      rescue StandardError
        return nil
      end

      def count_cron_runs(cron, deadline, limit)
        parsed = Rufus::Scheduler.parse_cron(cron)
        at = Time.now
        count = 0
        while count < limit
          at = parsed.next_time(at).to_t
          break if at > deadline
          count += 1
        end
        return count
      end
    end
  end
end
