require 'icalendar-rrule'

module TomatoShrieker
  class IcalendarSource < Source
    using Icalendar::Scannable
    include CommandRunner
    include GoogleCalendarFixable

    def initialize(params)
      super
      @http = HTTP.new
    end

    def default_cron
      return '0 0 * * *'
    end

    def default_period
      return nil
    end

    # コマンドの `command` / `dir` / `env` は `/source/ical` の下に置く (#1691)。
    # ⚠ `/source/command` は `CommandSource` の判別キーなので、同じ名前を使うと
    # 1 つの定義から 2 つのソースが立つ。
    def command_root
      return '/source/ical'
    end

    def ical
      return command_ical if command?
      return Icalendar::Calendar.parse(@http.get(uri)).first
    end

    # コマンドの標準出力を iCalendar として読む (#1691)。
    #
    # ⚠ **空の出力は「該当なし」で正常。**予定 0 件の `VCALENDAR` と同じに扱う。
    # 🔴 **空でないのに読めない出力は例外にする。**パーサは入力によっては例外を出さず
    # 何も返さないだけなので、そのままだと壊れたコマンドが「予定なし」の success を
    # 積み続ける。⚠ ここまでは取得段（`exec` が `entries.to_a` を先に評価している）。
    # ⚠ **パーサの例外をそのまま上げない。**メッセージに出力の値がそのまま入るので、
    # 資格情報を伏せられない（例外メッセージは run_log・`/status.json`・Sentry へ流れる）。
    # 🔴 **例外の型で絞らない（4.16.0 リリース前レビュー）。**`ParseError` が上がるのは strict
    # モードだけで、実際に上がるのは `Icalendar::Values::Date::FormatError`（`ArgumentError`
    # の子・`Failed to parse "<値>"`）など。`ParseError` だけ受けていたときは素通しだった。
    def command_ical
      output = run_command
      return Icalendar::Calendar.new if output.blank?
      begin
        ical = Icalendar::Calendar.parse(output).first
      rescue StandardError
        ical = nil
      end
      # ⚠ 伏せてから切り詰める。先に切ると、途中で切れた資格情報が伏せ字に一致しなくなる。
      return ical if ical
      raise "invalid iCalendar output: #{command.masked(output.strip).ellipsize(100)}"
    end

    def exec
      return if disable?
      in_threads = Parallel.processor_count * 2
      # 🔴 **`entries` を取り出してから段を立てる (#1586)。**⚠ ical の取得に失敗した
      # run は取得段。⚠⚠ 予定は時刻で 1 度しか流れないので、エントリ処理段で落ちた
      # ぶんは**取り返せない**。
      #
      # 🔴🔴 **`to_a` で先に評価する (#1615 の Codex P1)。**⚠⚠ `entries` は
      # `enum_for` ＝ **Enumerator なので、代入しただけでは ical を取りに行かない**。
      # しかも Enumerator は `empty?` を持たないので `present?` が**中身を見ずに true**
      # を返す。そのままだと**段を立てた後に `ical` の HTTP / パースが落ちる**ことに
      # なり、取得段の失敗が `entry_stage: true` で保存される。
      targets = entries.to_a
      @delivery_stats&.enter_entry_stage! if targets.present?
      Parallel.each(targets, in_threads:) do |entry|
        template = create_template
        template[:entry] = entry
        template[:remind] = false
        shriek(template:, visibility:)
      end
    end

    def remind
      return if disable?
      return unless remind?
      in_threads = Parallel.processor_count * 2
      Parallel.each(entries.select {|v| remind_entry?(v)}, in_threads:) do |entry|
        template = create_template
        template[:entry] = entry
        template[:remind] = true
        shriek(template:, visibility:, stats: nil)
      end
    rescue => e
      logger.error(source: id, error: e)
    end

    def summary
      return {id:, entries: entries.reject {|v| ignore_entry?(v)}.to_a}
    end

    def keyword
      return nil unless keyword = self['/source/keyword']
      return Regexp.new(keyword)
    end

    def negative_keyword
      return nil unless keyword = self['/source/negative_keyword']
      return Regexp.new(keyword)
    end

    def days
      return self['/source/days'] || 3
    end

    def entries(&block)
      return enum_for(__method__) unless block
      ical.events
        .map {|event| create_entry(event)}
        .sort_by {|entry| entry[:start_date]}
        .reject {|entry| ignore_entry?(entry)}
        .each(&block)
    end

    def ignore_entry?(entry)
      return true if keyword && !hot_entry?(entry)
      return true if negative_keyword && negative_entry?(entry)
      return true unless shriekable?(entry[:start_date], entry[:end_date])
      return false
    end

    def remind_entry?(entry)
      return false if entry[:all_day]
      time_start = Time.now
      time_end = time_start + remind_every.minutes
      return (time_start..time_end).cover?(entry[:start_date])
    end

    def hot_entry?(entry)
      return entry[:title].match?(keyword) || entry[:body].match?(keyword)
    end

    def negative_entry?(entry)
      return true if entry[:title].match?(negative_keyword)
      return true if entry[:body].match?(negative_keyword)
      return false
    end

    def create_entry(event)
      # ⚠ **`DTEND` は `scan_rrule` より先に補う (#1693)。**icalendar-rrule は `DTEND` が無いと
      # `DTSTART` の `to_i` で終了を作るが、終日（`Icalendar::Values::Date`）は `to_i` を持たず落ちる。
      event.dtend ||= event.dtstart
      event = scan_rrule(event) if event.rrule.present?
      start_date = Time.parse(event.dtstart.to_s).getlocal
      end_date = Time.parse(event.dtend.to_s).getlocal
      data = {
        start_date:,
        end_date:,
        is_today: today?(start_date, end_date),
        countdown: countdown(start_date),
        title: fedi_sanitize(event.summary),
        body: fedi_sanitize(event.description),
        location: fedi_sanitize(event.location),
        all_day: all_day?(event.dtstart) && all_day?(event.dtend),
      }
      data = fix_google_calendar_entry(data) if google?
      return data
    end

    def templates
      @templates ||= {
        default: Template.new(self['/dest/template'] || 'calendar'),
      }
      return @templates
    end

    def uri
      uri = Ginseng::URI.parse(self['/source/calendar'])
      uri ||= Ginseng::URI.parse(self['/source/ical'])
      return nil unless uri&.absolute?
      uri.query_values = {t: Time.now.to_f.to_s}
      return uri.normalize
    end

    def register
      return if disable?
      prepare_command if command?
      schedule_remind if remind?
      return super
    end

    def remind?
      return self['/schedule/remind/enable'] == true
    end

    def remind_minutes
      return nil unless remind?
      return self['/schedule/remind/minutes'] || 5
    end

    alias remind_every remind_minutes

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.grep(self).each(&block)
    end

    private

    def start_time_today
      return Time.parse(Time.now.strftime('%Y/%m/%d 00:00:00'))
    end

    def today?(start_date, end_date)
      start_date = Time.parse(start_date.strftime('%Y/%m/%d 00:00:00'))
      end_date = Time.parse(end_date.strftime('%Y/%m/%d 23:59:59'))
      return (start_date..end_date).cover?(start_time_today)
    end

    def countdown(start_date)
      start_date = Time.parse(start_date.strftime('%Y/%m/%d 00:00:00')).to_date
      return Date.today.upto(start_date).count - 1
    end

    def all_day?(date)
      return true if date.is_a?(Icalendar::Values::Date)
      return true if date.to_s.include?('00:00:00')
      return false
    end

    def shriekable?(start_date, end_date)
      start_date = Time.parse((start_date - days.days).strftime('%Y/%m/%d 00:00:00'))
      end_date = Time.parse(end_date.strftime('%Y/%m/%d 23:59:59'))
      return (start_date..end_date).cover?(start_time_today)
    end

    def scan_rrule(event)
      calendar = Icalendar::Calendar.new
      calendar.event do |e|
        e.dtstart = event.dtstart
        e.dtend = event.dtend
        e.summary = event.summary
        e.description = event.description
        e.location = event.location
        e.rrule = event.rrule.first
      end
      if e = calendar.scan(Date.today, Date.today + days.days).first
        event.dtstart = e.start_time
        event.dtend = e.end_time
      end
      return event
    end

    def schedule_remind
      every = "#{remind_every}m"
      job = Scheduler.instance.scheduler.every(every, {tag: id, overlap: false}) do
        logger.info(source: id, class: self.class.to_s, action: 'remind start')
        remind
        logger.info(source: id, class: self.class.to_s, action: 'remind end')
      rescue => e
        logger.error(source: id, error: e)
      end
      logger.info(source: id, job:, class: self.class.to_s, remind: true, every:)
      return job
    end
  end
end
