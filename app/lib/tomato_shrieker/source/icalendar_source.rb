require 'icalendar-rrule'

module TomatoShrieker
  class IcalendarSource < Source
    using Icalendar::Scannable

    attr_reader :ical

    def initialize(params)
      super
      @http = HTTP.new
      @ical = Icalendar::Calendar.parse(@http.get(uri)).first
    end

    def default_cron
      return '0 0 * * *'
    end

    def default_period
      return nil
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
      return true unless ((entry[:start_date] - days.days)..entry[:end_date]).cover?(Time.now)
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
      return {
        start_date: Time.parse(event.dtstart.to_s).getlocal,
        end_date: Time.parse(event.dtend.to_s).getlocal,
        is_today: Time.parse(event.dtstart.to_s).today?,
        title: event.summary&.sanitize,
        body: event.description&.sanitize,
        location: event.location&.sanitize_status,
        all_day: event.dtstart.is_a?(Icalendar::Values::Date),
      }
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
      uri.query_values = {t: rand(1000..9999)}
      return uri
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.select {|s| s.is_a?(self)}.each(&block)
    end

    private

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
