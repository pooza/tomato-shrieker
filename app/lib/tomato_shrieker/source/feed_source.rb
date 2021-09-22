require 'feedjira'

module TomatoShrieker
  class FeedSource < Source
    def initialize(params)
      super
      @http = HTTP.new
      @http.base_uri = uri
    end

    def exec(options = {})
      if multi_entries?
        shriek(template: multi_entries_template, visibility: visibility)
      elsif options['silence']
        touch
      elsif touched? || options['all']
        fetch(&:shriek)
        logger.info(source: id, message: 'crawl')
      elsif entry = fetch.to_a.last
        entry.shriek
      end
    end

    def purge(params = {})
      return unless purge?
      records = Entry.dataset
        .select(:published)
        .where(feed: hash)
        .order {published.desc}
        .limit(1)
        .offset(feedjira.entries.count * expire)
      return unless date = records.first&.published
      records = Entry.dataset.where(feed: hash).where(
        Sequel.lit("published < '#{date.strftime('%Y-%m-%d %H:%M:%S %z')}'"),
      )
      records.destroy unless params[:dryrun]
      return date
    end

    def purge?
      return self['/source/purge'] unless self['/source/purge'].nil?
      return true
    end

    def expire
      return self['/source/expire'] || 2
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
      entries = feedjira.entries
        .select {|v| v.categories.member?(category)}
        .sort_by {|v| v.published.to_f}
        .reverse
        .first(limit)
      return entries
    end

    def multi_entries_template
      return nil unless multi_entries?
      template = Template.new(template_name)
      template[:entries] = multi_entries
      return template
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
      Entry.create(feedjira.entries.max_by(&:published), self)
      logger.info(source: id, message: 'touch')
    end

    def fetch
      return enum_for(__method__) unless block_given?
      feedjira.entries.sort_by {|entry| entry.published.to_f}.each do |entry|
        next if keyword && !hot_entry?(entry)
        next if negative_keyword && negative_entry?(entry)
        next unless record = Entry.create(entry, self)
        yield record
      rescue => e
        logger.error(error: e)
      end
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
      return feedjira.entries.present?
    end

    def uri
      uri = Ginseng::URI.parse(self['/source/feed'])
      uri ||= Ginseng::URI.parse(self['/source/url'])
      return nil unless uri&.absolute?
      return uri
    end

    def feedjira
      return Feedjira.parse(@http.get(uri).body)
    rescue Feedjira::NoParserAvailable => e
      raise Ginseng::GatewayError, "Invalid feed #{uri} #{e.message}"
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

    def self.purge_all(params = {})
      logger = Logger.new
      FeedSource.all do |source|
        next unless date = source.purge(params)
        logger.info(source: source.id, message: 'purge', date: date, params: params)
        puts "#{source.id}: #{message} #{date} #{params[:dryrun] ? 'dryrun' : ''}" if params[:echo]
      rescue => e
        logger.error(error: e, source: source.id, params: params)
        warn "#{source.id}: #{e.message} #{params[:dryrun] ? 'dryrun' : ''}" if params[:echo]
      end
    end
  end
end
