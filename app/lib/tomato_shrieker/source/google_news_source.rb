module TomatoShrieker
  class GoogleNewsSource < FeedSource
    SIMILARITY_THRESHOLD = 0.4
    DEDUPE_HOURS = 48

    def uri
      return cleaner_uri if cleaner_uri
      if self['/source/news/phrase']
        uri = Ginseng::URI.parse(config['/google/news/urls/root'])
        values = uri.query_values || {}
        values['q'] = self['/source/news/phrase']
        uri.query_values = values
      else
        uri = Ginseng::URI.parse(self['/source/news/url'])
      end
      return uri.normalize if uri&.absolute?
    end

    def phrase
      return self['/source/news/phrase'] || uri.query_values['q']
    end

    def dedupe?
      return self['/source/news/dedupe'] != false
    end

    def ignore_entry?(entry)
      return true if super
      return true if dedupe? && similar_entry?(entry)
      return false
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.grep(self).each(&block)
    end

    def cleaner?
      return cleaner_uri.present?
    end

    private

    def cleaner_uri
      base = self['/source/news/cleaner/url'] || config['/google/news/cleaner/url']
      return nil unless base
      phrase = self['/source/news/phrase']
      return nil unless phrase
      uri = Ginseng::URI.parse(base)
      uri.query_values = {'q' => phrase}
      return uri.normalize
    end

    def similar_entry?(entry)
      title = normalize_title(entry.title)
      bigrams = to_bigrams(title)
      return false if bigrams.empty?
      recent_entries(entry).any? do |existing|
        other = to_bigrams(normalize_title(existing[:title]))
        next false if other.empty?
        jaccard(bigrams, other) >= SIMILARITY_THRESHOLD
      end
    end

    def recent_entries(entry)
      since = (entry.published || Time.now) - (DEDUPE_HOURS * 3600)
      Entry.dataset
        .where(feed: hash)
        .where {published >= since}
        .select(:title)
    end

    def normalize_title(title)
      return title.to_s.sub(/\s+[-–—|]\s+\S+\z/, '').strip
    end

    def to_bigrams(str)
      chars = str.chars
      return Set.new if chars.size < 2
      Set.new(chars.each_cons(2).map(&:join))
    end

    def jaccard(set_a, set_b)
      intersection = (set_a & set_b).size
      union = (set_a | set_b).size
      return 0.0 if union.zero?
      intersection.to_f / union
    end
  end
end
