require 'icalendar'

module TomatoShrieker
  class IcalendarSource < Source
    attr_reader :ical

    def initialize(params)
      super
      @http = HTTP.new
      @ical = Icalendar.parse(@http.get(uri), true)
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

    def entries(&block)
      return enum_for(__method__) unless block
      ical.events
        .sort_by {|entry| entry.dtstart.to_f}
        .each {|entry| create_entry(entry)}
        .each(&block)
    end

    def ignore_entry?(entry)
      return true if keyword && !hot_entry?(entry)
      return true if negative_keyword && negative_entry?(entry)
      return false
    end

    def hot_entry?(entry)
      return entry.summary&.match?(keyword) || entry.description&.match?(keyword)
    end

    def negative_entry?(entry)
      return true if entry.summary&.match?(negative_keyword)
      return true if entry.description&.match?(negative_keyword)
      return false
    end

    def create_entry(entry)
      entry.start_date = entry.dtstart.getlocal
      entry.end_date = entry.dtend.getlocal
      entry.title = entry.summary&.escape_status
      entry.body = entry.summary&.description
      return entry
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
