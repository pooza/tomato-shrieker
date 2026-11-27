module TomatoShrieker
  # `/source/keyword` / `/source/negative_keyword` の読み方。`FeedSource` と `IcalendarSource` が
  # 同じものを持っていたので切り出した（#1781）。
  module KeywordFilterable
    KEYS = ['keyword', 'negative_keyword'].freeze

    def keyword
      return nil unless keyword = self['/source/keyword']
      return Regexp.new(keyword)
    end

    def negative_keyword
      return nil unless keyword = self['/source/negative_keyword']
      return Regexp.new(keyword)
    end

    # 🔴 **正規表現として読めない値を弾く（#1781）。**スキーマは `type: string` しか見ないので `'('` も通り、
    # run のたびに `RegexpError` で落ちる（起動は倒れないので `source reload` の拒否には入れない）。
    # `SourceValidator.validate` が呼ぶ。⚠ メッセージに値を入れない（`SourceValidator.readable` と同じ）。
    def self.errors(params)
      return [] unless (source = params['source']).is_a?(Hash)
      return KEYS.filter_map do |key|
        next unless source[key].is_a?(String)
        next if (Regexp.new(source[key]) rescue nil)
        next "/source/#{key}: 正規表現として読めません"
      end
    end
  end
end
