require 'icalendar'

module TomatoShrieker
  class IcalendarSource < Source
    attr_reader :ical

    def initialize(params)
      super
      @http = HTTP.new
      @ical = Icalendar::Calendar.parse(@http.get(uri)).first
    end

    def exec
      shriek(template: create_template, visibility:)
    rescue => e
      e.package = Package.full_name
      SlackService.broadcast(e)
      logger.error(source: id, error: e)
    end

    def create_template(type = :calendar, status = nil)
      template = super
      template[:entries] = entries
      return template
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
        .reject {|event| ignore_event?(event)}
        .sort_by {|event| event.dtstart.strftime('%Y/%m/%d %R')}
        .map {|event| create_entry(event)}
        .each(&block)
    end

    def ignore_event?(entry)
      return true if keyword && !hot_event?(entry)
      return true if negative_keyword && negative_event?(entry)
      start_date = Time.parse(entry.dtstart.to_s)
      end_date = Time.parse(entry.dtend.to_s)
      return true unless ((start_date - days)..end_date).cover?(Time.now)
      return false
    end

    def hot_event?(entry)
      return entry.summary&.match?(keyword) || entry.description&.match?(keyword)
    end

    def negative_event?(entry)
      return true if entry.summary&.match?(negative_keyword)
      return true if entry.description&.match?(negative_keyword)
      return false
    end

    def create_entry(event)
      return {
        start_date: Time.parse(event.dtstart.to_s).getlocal,
        end_date: Time.parse(event.dtend.to_s).getlocal,
        title: event.summary&.escape_status,
        body: event.description&.escape_status,
        location: event.location&.escape_status,
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
      return uri
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.select {|s| s.is_a?(self)}.each(&block)
    end
  end
end
