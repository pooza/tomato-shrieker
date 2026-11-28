module TomatoShrieker
  class GoogleNewsSourceTest < TestCase
    def test_all
      assert_kind_of(Enumerator, GoogleNewsSource.all)
    end

    # 🔴 **#1694: cleaner を設定していなくても、Google News のソースを作れること。**
    #
    # ⚠ `application.yaml` の既定は `null` で、`Config#[]` は値の無いキーを `ConfigError` に
    # する。`FeedSource#initialize` が `uri` を呼ぶので、そのまま読むと `new` の時点で落ちる。
    # ⚠ `test/sources/` に news のソースが無く、下の `all` を回すテストは CI で 1 度も
    # 回っていなかった。
    def test_uri_without_cleaner
      config.delete('/google/news/cleaner/url')
      source = build_source

      assert_false(source.cleaner?)
      assert_equal('news.google.com', source.uri.host)
      assert_equal('プリキュア', source.uri.query_values['q'])
    end

    # 🔴 #1704: cleaner を使うかを登録のたびにログへ出す（黙って直読みへ倒れたことに気づけるように）。
    def test_register_logs_cleaner
      config['/google/news/cleaner/url'] = 'http://cleaner.example.test:3000/clean'
      source = build_source
      logged = []
      source.logger.define_singleton_method(:info) {|message| logged.push(message)}
      source.define_singleton_method(:schedule) {|*| nil}
      source.register

      assert_true(logged.any? {|v| v.is_a?(Hash) && v[:cleaner] == true})
    end

    def test_uri_with_cleaner
      config['/google/news/cleaner/url'] = 'http://cleaner.example.test:3000/clean'
      source = build_source

      assert_predicate(source, :cleaner?)
      assert_equal('cleaner.example.test', source.uri.host)
      assert_equal('プリキュア', source.uri.query_values['q'])
    end

    # ⚠ ソースごとの指定は、全体の設定より優先する。
    def test_uri_with_source_cleaner
      config.delete('/google/news/cleaner/url')
      source = build_source('cleaner' => {'url' => 'http://own.example.test/clean'})

      assert_equal('own.example.test', source.uri.host)
    end

    # ⚠ cleaner は検索語（`phrase`）にしか使えない。`url` 指定のソースはそのまま読む。
    def test_uri_with_url
      config['/google/news/cleaner/url'] = 'http://cleaner.example.test:3000/clean'
      source = GoogleNewsSource.new(
        'id' => '__test_google_news_url__',
        'source' => {'news' => {'url' => 'https://news.google.com/rss/topics/x'}},
        'dest' => {'hooks' => ['https://hook.example.test/news']},
      )

      assert_false(source.cleaner?)
      assert_equal('/rss/topics/x', source.uri.path)
    end

    # 🔴 **#1820: 同じ run の候補どうしも類似判定にかける。**本番では同じ取得に入った
    # 各社配信（ほぼ同じタイトル）が 9 件そのまま投稿されていた。
    def test_target_entries_dedupe_within_run
      source = build_source
      deliverable!(source)
      stub_entries(source, [
        '【きょうから第2弾】マクドナルド、ハッピーセットは「名探偵プリキュア！」 “こものいれ”など3種 - ORICON NEWS',
        '【きょうから第2弾】マクドナルド、ハッピーセットは「名探偵プリキュア！」 “こものいれ”など3種 - Yahoo!ニュース',
        '【きょうから第2弾】マクドナルド、ハッピーセットは「名探偵プリキュア！」　“こものいれ”など3種 - au Webポータル',
        '名探偵プリキュア! × スイパラ 11月26日よりコラボカフェ開催! - コラボカフェ',
      ])
      titles = source.target_entries.map(&:title)

      assert_equal(2, titles.size)
      assert_match(/ORICON/, titles.first)
      assert_match(/スイパラ/, titles.last)
    end

    # ⚠ `dedupe: false` なら同じ run でも畳まない。
    def test_target_entries_without_dedupe
      source = build_source('dedupe' => false)
      stub_entries(source, ['同じタイトル - A', '同じタイトル - B'])

      assert_equal(2, source.target_entries.count)
    end

    # ⚠ 48 時間より離れていれば、同じ run でも別の記事として扱う（DB との比較と同じ窓）。
    def test_target_entries_window
      source = build_source
      deliverable!(source)
      now = Time.now
      stub_entries(source, ['同じタイトルの記事 - A', '同じタイトルの記事 - B'], [now - (72 * 3600), now])

      assert_equal(2, source.target_entries.count)
    end

    # ⚠ 流れない候補（`feed.time` より古い）は、同じ run の類似記事を落とさない（#1822 の Codex P2）。
    # 落とすと、古い方は `Entry.deliverable` で捨てられ、新しい方は類似で捨てられ、どちらも流れない。
    def test_target_entries_ignores_undeliverable
      source = build_source
      now = Time.now
      source.define_singleton_method(:touched?) {true}
      source.define_singleton_method(:time) {now - 3600}
      stub_entries(source, ['同じタイトルの記事 - A', '同じタイトルの記事 - B'], [now - 7200, now])

      assert_equal(2, source.target_entries.count)
    end

    # 候補がすべて流れる状態にする（touch 済み・`feed.time` は候補より前）。
    def deliverable!(source)
      source.define_singleton_method(:touched?) {true}
      source.define_singleton_method(:time) {Time.now - (30 * 24 * 3600)}
    end

    def stub_entries(source, titles, times = nil)
      now = Time.now
      items = titles.each_with_index.map do |title, i|
        Struct.new(:title, :published, :url).new(title, times ? times[i] : now + i, "https://example.test/#{i}")
      end
      source.define_singleton_method(:entries) {items}
    end

    def build_source(news = {})
      return GoogleNewsSource.new(
        'id' => "__test_google_news_#{SecureRandom.hex(4)}__",
        'source' => {'news' => {'phrase' => 'プリキュア'}.merge(news)},
        'dest' => {'hooks' => ['https://hook.example.test/news']},
      )
    end

    def test_phrase
      GoogleNewsSource.all do |source|
        assert_kind_of(String, source.phrase)
        assert_predicate(source.phrase, :present?)
      end
    end
  end
end
