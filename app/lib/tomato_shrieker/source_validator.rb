# frozen_string_literal: true

require 'json-schema'

module TomatoShrieker
  # 単一ソース定義（config/sources/<id>.yaml）を config/schema/source.yaml で検証する。
  class SourceValidator
    include Package

    JSON::Validator.use_multi_json = false

    SCHEMA_FILE = 'config/schema/source.yaml'

    # ⚠ `IcalendarSource#remind_minutes` の既定と同じ値。ずれると「省略時は倒れないのに
    # 明示すると倒れる」（またはその逆）になる。
    DEFAULT_REMIND_MINUTES = 5

    # しきい値への到達性を見るとき、cron の発火を最大何件まで並べるか。⚠ 1 件 80µs 前後
    # （fugit の next_time）なので、`* * * 1-11 *` のような密で長周期の指定でも
    # `source validate` が 1 秒ほどで返るように抑える。超えたら判定を諦めて警告しない。
    MAX_CRON_SAMPLES = 10_000

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
        return errors.concat(startup_errors(params))
      end

      # 🔴 **起動なら倒れる定義の指摘を全部返す（4.10.0 リリース前レビュー）。**
      # `source validate` と `source reload` の拒否が**同じこの 1 本**を見る。
      #
      # ⚠⚠ **判別キーの不一致（unmatched）もここで見る。**スキーマの `source` は
      # `minProperties: 1` しか要求しないので `source: {keyword: ...}` も通るが、
      # `register_all` は `no source class matched` で倒れる (#1572)。
      # 以前は reload の拒否が `Source.all` を回していたので、**定義上 `Source.all` に
      # 現れない unmatched を原理的に検査できず**、reload は通るのに次の再起動で
      # 全ソースが止まる形になっていた。
      def startup_errors(params)
        params = params.deep_stringify_keys
        return [] if params['disable'] == true
        return [unmatched_error] unless Source.matched?(params)
        return schedule_errors(params)
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
      #
      # 🔴 **実体を作って、`register` が実際に使うスケジュールを見る（#1590 / #1600 の Codex P2）。**
      # ⚠⚠ 生の params を読むと、`IcalendarSource` の既定 cron（`0 0 * * *`）が `every` より
      # 優先されることを見落とし、**`every: '0s'` を書いた ical 定義を「起動はできるのに
      # reload は拒否される」**にする。⚠ 実体の生成が例外になる定義は、起動の
      # `Source.all` でも同じ例外で倒れるので、それ自体を指摘として返す。
      # ⚠⚠ **rescue は実体の生成だけに掛ける（#1601 の Codex P2）。**検査側の不備
      # （Hash でない `schedule` での `dig` など）まで拾うと、起動は既定の schedule で
      # 通るのに reload を拒否する。
      def schedule_errors(params)
        params = params.deep_stringify_keys
        return [] if params['disable'] == true
        begin
          sources = matched_sources(params)
        rescue StandardError => e
          return ["/source: #{e.message}"]
        end
        errors = sources.map {|source| main_schedule_error(source)}
        errors.push(remind_error(params)) if remind_scheduled?(params)
        return errors.compact.uniq
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
      # 食い違いを、向きだけ変えて自分で作ることになる。⚠ 優先順も既定値も
      # `Source#schedule_spec` が `register` と同じアクセサで持っているので、ここへ書き写さない。
      def main_schedule_error(source)
        spec = source.schedule_spec
        return schedule_error(spec[:value], spec[:type])
      end

      # 🔴 **remind は本体のスケジュールと別に立つ（#1570 の Codex P1）。**
      # `IcalendarSource#register` は `schedule_remind` を**本体より先に**呼び、
      # `"#{minutes}m"` を `scheduler.every` へ渡す。⚠⚠ `minutes: 0` は
      # `parse_duration` では通る（0 を返すだけ）が、`every` が
      # `cannot schedule ... with a frequency of 0` で倒れる＝**起動が落ちる**。
      #
      # ⚠ **`key_flatten` で読む。**`IcalendarSource#remind_minutes` と同じ読み方にしておけば、
      # スキーマ違反の `schedule: broken` でも起動と同じく「値が無い」になる（`dig` は倒れる）。
      def remind_error(params)
        minutes = params.key_flatten['/schedule/remind/minutes'] || DEFAULT_REMIND_MINUTES
        # ⚠⚠ **型で弾かず、`schedule_remind` と同じ `"#{minutes}m"` を組んで引く（レビュー黄 0）。**
        # 型違いはスキーマの担当だが、**`source reload` は意図的にスキーマを見ない**ので、
        # 文字列の `'0'` を見送ると**誰も見ないまま起動だけが倒れる**。
        return schedule_error("#{minutes}m", 'every', label: '/schedule/remind/minutes')
      end

      # ⚠ **remind ジョブを立てるクラスにマッチする定義だけを見る。**`schedule.remind` は
      # スキーマ上どのソースにも書けるが、**立てるのは `IcalendarSource` だけ**。
      # 他のソースでは無視される設定なので、ここで NG にすると上と同じ食い違いになる。
      def remind_scheduled?(params)
        return false unless params.key_flatten['/schedule/remind/enable'] == true
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

      def unmatched_error
        keys = Source.classes.map {|v| v[:config].delete_prefix('/')}
        return "/source: no source class matched (#{keys.join(' / ')} のいずれかが必要です)"
      end

      # 🔴 **`register` と同じ rufus の入口（`at` / `cron` / `every`）へ実際に通す（#1598 の Codex P1）。**
      #
      # ⚠⚠ 以前はキーごとのパーサ（`parse_at` / `parse_cron` / `parse_duration`）を呼び、
      # 文字列以外は「型違いはスキーマの担当」として見送っていた。**`source reload` は
      # スキーマを見ない**ので、`every: 0`（YAML では数値）や `cron: 42` は誰も見ないまま
      # 起動だけが倒れていた。しかもパーサだけでは入口の検査に届かない:
      # - `parse_duration('0s')` は 0 を返すだけで、`every` の「頻度 0 以下」は弾かない
      # - `every` は scheduler の frequency（既定 0.3 秒）より細かい指定も倒れる
      # - `at` に数値を渡すと scheduler は `InJob` を立てる（`AtJob` の検査とは別の道）
      # → **分岐を書き写さず、同じ入口に通して立ったジョブをすぐ消す。**
      # ⚠ 総称の `Rufus::Scheduler.parse` を使ってはいけない（cron 文字列を `every` に
      # 書いた取り違えを見逃す）。キーの名前のメソッドを呼ぶこと。
      def schedule_error(value, key, label: "/schedule/#{key}")
        job = validation_scheduler.public_send(key, value, job: true) {nil}
        job&.unschedule
        return nil
      rescue StandardError => e
        return "#{label}: #{e.message}"
      end

      # ⚠ **検査専用の scheduler。**`Scheduler.instance` を使うと、daemon の中から呼ばれたときに
      # 本物のジョブ表へ一瞬でも混ざる。
      def validation_scheduler
        @validation_scheduler ||= Rufus::Scheduler.new
        return @validation_scheduler
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
            "必要ですが、/monitor/retention_days (#{retention} 日) のどの窓でも発火は" \
            "最大 #{runs} 回だけです。prune で先に消えるため、連続して失敗しても 503 になりません",
        ]
      end

      # retention 幅の窓に**最大で**何回発火するか。⚠ `limit` に届いた時点で打ち切る。
      #
      # 🔴 **回数を実際に数える（Codex P2・#1587）。**⚠⚠ 以前は「次の 2 回の間隔」を
      # 全体へ引き伸ばしていたので、**平日限定 cron のような不均一な指定で所要日数を
      # 過小評価した**。しかも **`source validate` を叩いた曜日で結果が変わる**。
      #
      # 🔴 **窓の起点を「今」に固定しない（#1594 の Codex P2）。**prune は「今から retention
      # 日より古い行」を消すだけなので、**どこかの時点で窓に `limit` 回入れば 503 に届く**。
      # ⚠⚠ `0 0 1,2 * *` にしきい値 2 は、月の半ばに数えると次の 14 日で 0 回だが、
      # 1 日と 2 日の失敗は同じ窓に入る。→ **発火を並べて、窓をずらして最大を取る。**
      #
      # 🔴 **マッチした全インスタンスの発火を合わせる（#1594 の Codex P2）。**1 つの定義が
      # 複数のクラスにマッチすると、scheduler はそのぶんジョブを立て、どれも同じソース ID の
      # 行を書く。⚠ 合わせ方は**各インスタンスの最大の和**（上限）。WARN は助言なので、
      # 位相の重なりまで厳密に解くより「出しすぎない」側に倒す。
      #
      # ⚠ 壊れた cron / period や、走査の上限に達して最大を確定できないときは nil
      # （＝ 警告しない）。**警告を出す処理が例外で倒れて `source validate` 全体を止めるほうが
      # 害が大きい**し、書式そのものの誤りは `startup_errors` と起動時の register が別に捕まえる。
      def runs_within_retention(params, retention, limit)
        sources = matched_sources(params).reject(&:post_at)
        return nil if sources.empty?
        width = retention * 86_400
        runs = sources.map {|source| max_source_runs(source, width, limit)}
        return nil if runs.include?(nil)
        return [runs.sum, limit].min
      rescue StandardError
        return nil
      end

      def max_source_runs(source, width, limit)
        return max_cron_runs(Rufus::Scheduler.parse_cron(source.cron), width, limit) if source.cron
        return nil unless period = source.period
        return nil unless (seconds = Rufus::Scheduler.parse_duration(period)).positive?
        # ⚠ **固定間隔は数えずに計算する（#1602 の Codex P2）。**`every: 1s` に巨大なしきい値を
        # 置かれると、並べるだけで数千万件になる。窓 `(t - width, t]` に入るのは ceil 回。
        return [(width / seconds).ceil, limit].min
      end

      # ⚠ **走査する範囲は cron の周期で決める。**日・月の指定が無ければ週で一巡するので
      # 1 週間ぶんで足りる。あれば 1 年ぶんに加え、**次の 2 月 29 日の前後も見る**
      # （#1602 の Codex P2: `0 0 28,29 2 *` は閏年にだけ 2 回が同じ窓に入る）。
      def max_cron_runs(cron, width, limit)
        samples = 0
        return cron_ranges(cron, width).map do |from, to|
          max = 0
          window = []
          at = from
          while (at = cron.next_time(at).to_t) <= to
            return nil if MAX_CRON_SAMPLES < (samples += 1)
            window.push(at)
            window.shift while window.first <= at - width
            max = [max, window.size].max
            break if limit <= max
          end
          max
        end.max
      end

      def cron_ranges(cron, width)
        now = Time.now
        return [[now, now + (7 * 86_400) + width]] if weekly_cycle?(cron)
        leap_day = next_leap_day(now)
        return [[now, now + (366 * 86_400) + width], [leap_day - width, leap_day + width]]
      end

      # ⚠ `1#2`（第 2 月曜）や `5#-1`（最終金曜）は月で一巡するので週の周期に含めない。
      def weekly_cycle?(cron)
        return false if cron.months || cron.monthdays
        return (cron.weekdays || []).all? {|v| v.size == 1}
      end

      def next_leap_day(now)
        year = now.year
        year += 1 until Date.leap?(year) && now < Time.new(year, 2, 29)
        return Time.new(year, 2, 29)
      end
    end
  end
end
