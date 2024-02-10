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

    def prefix
      return super || ical.custom_properties['x_wr_calname'].first.to_s rescue nil
    end

    def entries(&block)
      return enum_for(__method__) unless block
      ical.events
        .reject {|event| ignore_event?(event)}
        .sort_by {|event| event.dtstart.to_f}
        .map {|event| create_entry(event)}
        .each(&block)
    end

    def ignore_event?(entry)
      return true if keyword && !hot_event?(entry)
      return true if negative_keyword && negative_event?(entry)
      return true unless ((entry.dtstart - days.days)..entry.dtend).cover?(Time.now)
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

    def create_entry(entry)
      return {
        start_date: entry.dtstart.getlocal,
        end_date: entry.dtend.getlocal,
        title: entry.summary&.escape_status,
        body: entry.description&.escape_status,
        location: entry.location&.escape_status,
      }
    end

    alias events entries

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
