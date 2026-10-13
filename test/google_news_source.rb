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

    def build_source(news = {})
      return GoogleNewsSource.new(
        'id' => '__test_google_news__',
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
