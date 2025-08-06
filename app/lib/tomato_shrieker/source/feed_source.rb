require 'feedjira'

module TomatoShrieker
  class FeedSource < Source
    def initialize(params)
      super
      @http = HTTP.new
      @http.base_uri = uri
    end

    def exec
      Environment.setup_database
      if multi_entries?
        shriek(template: create_template(:multi), visibility:)
      elsif touched?
        fetch(&:shriek)
      elsif entry = fetch.to_a.last
        entry.shriek
      end
    rescue => e
      logger.error(source: id, error: e)
    ensure
      db&.disconnect
    end

    def purge
      return unless purgeable?
      dataset = Entry.dataset.where(feed: hash).where(
        Sequel.lit("published < '#{keep_years.years.ago.strftime('%Y-%m-%d %H:%M:%S.000000')}'"),
      )
      dataset.destroy
    end

    def purgeable?
      return keep_years.present?
    end

    alias purge? purgeable?

    def keep_years
      return self['/keep/years']
    end

    def clear
      dataset = Entry.dataset.where(feed: hash)
      dataset.destroy
    end

    def multi_entries?
      return self['/dest/multi_entries'] unless self['/dest/multi_entries'].nil?
      return false
    end

    def category
      return self['/dest/category']
    end

    def limit
      return self['/dest/limit'] || 5
    end

    def templates
      @templates ||= {
        default: Template.new(self['/dest/template'] || 'title'),
        lemmy: Template.new(self['/dest/lemmy/template'] || self['/dest/template'] || 'title'),
        piefed: Template.new(self['/dest/piefed/template'] || self['/piefed/template'] || 'title'),
        multi: Template.new(self['/dest/template'] || 'multi_entries'),
      }
      return @templates
    end

    def create_template(type = :default, status = nil)
      template = super
      template[:feed] = self
      template[:entries] = multi_entries if type == :multi
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

    def enclosure?
      return self['/enclosure/enable'] == true
    end

    def enclosure_negative_keyword
      return nil unless keyword = self['/enclosure/negative_keyword']
      return Regexp.new(keyword)
    end

    def multi_entries
      records = entries
        .select {|v| v.categories.member?(category)}
        .sort_by {|v| v.published.to_f}
        .reverse
        .first(limit)
      return records
    end

    def time
      unless @time
        records = Entry.dataset
          .select(:published)
          .where(feed: hash)
          .order(Sequel.desc(:published))
          .limit(1)
        @time = records.first&.published
      end
      return @time
    end

    def touched?
      return time.present?
    end

    def touch
      Entry.create(entries.max_by(&:published), self)
      logger.info(source: id, message: 'touch')
    end

    def entries(&block)
      return enum_for(__method__) unless block
      feedjira.entries
        .sort_by {|entry| entry.published.to_f}
        .each {|entry| entry.title = fedi_sanitize(entry.title)}
        .each(&block)
    end

    def fetch
      return enum_for(__method__) unless block_given?
      entries.reject {|v| ignore_entry?(v)}.each do |entry|
        next unless record = create_record(entry)
        yield record
      rescue => e
        logger.error(source: id, error: e)
      end
    end

    def ignore_entry?(entry)
      return true if keyword && !hot_entry?(entry)
      return true if negative_keyword && negative_entry?(entry)
      return false
    end

    def create_record(entry)
      return Entry.create(entry, self)
    end

    def hot_entry?(entry)
      return entry.title&.match?(keyword) || entry.summary&.match?(keyword)
    end

    def negative_entry?(entry)
      return true if entry.title&.match?(negative_keyword)
      return true if entry.summary&.match?(negative_keyword)
      return true if entry.content&.match?(negative_keyword)
      return false
    end

    def present?
      return entries.present?
    end

    def uri
      uri = Ginseng::URI.parse(self['/source/feed'])
      uri ||= Ginseng::URI.parse(self['/source/url'])
      return nil unless uri&.absolute?
      return uri
    end

    def feedjira
      return Feedjira.parse(@http.get(uri).body)
    rescue => e
      raise Ginseng::GatewayError, "Invalid feed #{id} (#{uri}) #{e.message}"
    end

    def prefix
      return super || feedjira.title
    end

    def create_uri(href)
      uri = @http.create_uri(href)
      uri.fragment ||= self.uri.fragment
      return uri
    end

    def summary
      values = {id:, category:, multi: multi_entries?}
      values[:entries] = entries.reject {|v| ignore_entry?(v)}.map do |entry|
        {
          date: entry.published.strftime('%Y/%m/%d %R'),
          title: entry.title,
          link: entry.url,
          ignore: ignore_entry?(entry),
        }
      end
      return values
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.select {|s| s.is_a?(self)}.each(&block)
    end

    def self.purge_all
      all.select(&:purgeable?).each(&:purge)
    end
  end
end
