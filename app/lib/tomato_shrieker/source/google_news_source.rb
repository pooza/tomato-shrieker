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

    # 🔴 **同じ run の候補どうしも比べる (#1820)。**`similar_entry?` は DB の行としか比べないので、
    # 同じ取得に入っている（＝まだ DB に無い）類似記事はすべて通っていた。Google News は
    # 同じニュースの各社配信をまとめて返すので、すり抜けの大半がこれだった（本番の 14 日分
    # 278 件のうち、逐次なら 182 件が落ちる）。⚠ `entries` は `published` の昇順なので、
    # 先に通したものが古い側＝ DB との比較（48 時間さかのぼる）と同じ窓になる。
    def target_entries
      return super unless dedupe?
      accepted = []
      return entries.reject do |entry|
        next true if ignore_entry?(entry)
        bigrams = to_bigrams(normalize_title(entry.title))
        published = entry.published || Time.now
        since = published - (DEDUPE_HOURS * 3600)
        next true if accepted.any? {|time, other| time >= since && similar_bigrams?(bigrams, other)}
        accepted.push([published, bigrams])
        false
      end
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.grep(self).each(&block)
    end

    def cleaner?
      return cleaner_uri.present?
    end

    # 🔴 **cleaner を使うかを登録のたびにログへ出す (#1704)。**`/google/news/cleaner/url` が無ければ
    # 黙って Google News を直接読む（#1694）ので、設定の綴りを誤っても、どこにも出なかった。
    def register
      logger.info(source: id, class: self.class.to_s, cleaner: cleaner?) unless disable?
      return super
    end

    private

    def cleaner_uri
      base = self['/source/news/cleaner/url'] || default_cleaner_url
      return nil unless base
      phrase = self['/source/news/phrase']
      return nil unless phrase
      uri = Ginseng::URI.parse(base)
      uri.query_values = {'q' => phrase}
      return uri.normalize
    end

    # ⚠ **未設定なら nil。**`application.yaml` の既定は `null` で、`Config#[]` は値の無いキーを
    # `ConfigError` にする。そのまま読むと、cleaner を立てていない環境では Google News の
    # ソースを作った時点（`FeedSource#initialize` が `uri` を呼ぶ）で落ちる。
    def default_cleaner_url
      return config['/google/news/cleaner/url']
    rescue Ginseng::ConfigError
      return nil
    end

    def similar_entry?(entry)
      title = normalize_title(entry.title)
      bigrams = to_bigrams(title)
      return false if bigrams.empty?
      return recent_entries(entry).any? do |existing|
        similar_bigrams?(bigrams, to_bigrams(normalize_title(existing[:title])))
      end
    end

    def similar_bigrams?(bigrams, other)
      return false if bigrams.empty? || other.empty?
      return jaccard(bigrams, other) >= SIMILARITY_THRESHOLD
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
