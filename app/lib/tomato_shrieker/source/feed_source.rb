require 'feedjira'

module TomatoShrieker
  class FeedSource < Source
    def initialize(params)
      super
      @http = HTTP.new
      @http.base_uri = uri
    end

    def exec
      if multi_entries?
        template = template.clone
        template[:entries] = multi_entries
        shriek(template: template, visibility: visibility)
      elsif touched?
        fetch(&:shriek)
      elsif entry = fetch.to_a.last
        entry.shriek
      end
    end

    def purge
      records = Entry.dataset
        .select(:published)
        .where(feed: hash)
        .order {published.desc}
        .limit(1)
      return unless date = records.first&.published
      records = Entry.dataset.where(feed: hash).where(
        Sequel.lit("published < '#{date.strftime('%Y-%m-%d %H:%M:%S %z')}'"),
      )
      records.destroy
      return date
    end

    def unique_title?
      return self['/source/title/unique'] unless self['/source/title/unique'].nil?
      return true
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

    def template_name
      return self['/dest/template'] || 'title'
    end

    def keyword
      return nil unless self['/source/keyword']
      return Regexp.new(self['/source/keyword'])
    end

    def negative_keyword
      return nil unless self['/source/negative_keyword']
      return Regexp.new(self['/source/negative_keyword'])
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

    def entries
      return enum_for(__method__) unless block_given?
      feedjira.entries.sort_by {|entry| entry.published.to_f}.each do |entry|
        yield entry
      rescue => e
        logger.error(error: e)
      end
    end

    def fetch
      return enum_for(__method__) unless block_given?
      entries.reject {|v| ignore_entry?(v)}.each do |entry|
        next unless record = create_record(entry)
        yield record
      rescue => e
        logger.error(error: e)
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
      return false
    end

    def present?
      return entries.present?
    end

    def uri
      uri = Ginseng::URI.parse(self['/source/feed'])
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

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.select {|s| s.is_a?(FeedSource)}.each(&block)
    end
  end
end
