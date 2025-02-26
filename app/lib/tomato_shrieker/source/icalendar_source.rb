require 'icalendar-rrule'

module TomatoShrieker
  class IcalendarSource < Source
    using Icalendar::Scannable

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

    def ical
      return Icalendar::Calendar.parse(@http.get(uri)).first
    end

    def exec
      entries do |entry|
        template = create_template
        template[:entry] = entry
        shriek(template:, visibility:)
      end
    rescue => e
      e.package = Package.full_name
      SlackService.broadcast(e)
      logger.error(source: id, error: e)
    end

    def summary
      return {id:, entries: entries.to_a}
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

    def google?
      return true if self['/source/google'].nil?
      return self['/source/google']
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

    def hot_entry?(entry)
      return entry[:title].match?(keyword) || entry[:body].match?(keyword)
    end

    def negative_entry?(entry)
      return true if entry[:title].match?(negative_keyword)
      return true if entry[:body].match?(negative_keyword)
      return false
    end

    def create_entry(event)
      event = scan_rrule(event) if event.rrule
      event.dtend ||= event.dtstart
      start_date = Time.parse(event.dtstart.to_s).getlocal
      end_date = Time.parse(event.dtend.to_s).getlocal
      data = {
        start_date:,
        end_date:,
        is_today: today?(start_date, end_date),
        title: fedi_sanitize(event.summary),
        body: fedi_sanitize(event.description),
        location: fedi_sanitize(event.location),
        all_day: event.dtstart.is_a?(Icalendar::Values::Date),
      }
      data = fix_google_calendar_entry(data) if google?
      return data
    end

    def fix_google_calendar_entry(data)
      # Google Calendarで、終日予定の終了日が1日ずれる。
      data[:end_date] -= 1.days if data[:all_day] && (data[:start_date] < data[:end_date])

      lines = data[:body].split(/\r?\n/)
      lines.reject! {|line| line.match?(/^Google Meet に参加:/)}
      lines.reject! {|line| line.match?(/^Meet の詳細:/)}
      data[:body] = lines.join("\n").strip
      return data
    end

    def templates
      @templates ||= {
        default: Template.new(self['/dest/template'] || 'calendar'),
        lemmy: Template.new(self['/dest/lemmy/template'] || self['/dest/template'] || 'calendar'),
      }
      return @templates
    end

    def present?
      return entries.present?
    end

    def uri
      uri = Ginseng::URI.parse(self['/source/calendar'])
      uri ||= Ginseng::URI.parse(self['/source/ical'])
      return nil unless uri&.absolute?
      uri.query_values = {t: Time.now.to_f.to_s}
      return uri
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.select {|s| s.is_a?(self)}.each(&block)
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
  end
end
