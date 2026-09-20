module TomatoShrieker
  class EntryTest < TestCase
    # 🔴 **エントリはフィクスチャで作る。`disable?` は持たない (#1597)。**
    #
    # ⚠⚠ 以前は `return true if Entry.dataset.empty?` で `disable?` していたので、
    # **まっさらな DB では 7 件が丸ごと omission** だった。CI は毎回まっさらなので
    # **この 7 件は CI で一度も走っていない**。手元では前の run が残したエントリの
    # 有無で結果が変わり、同じコミットで omission 数が振れた
    # ＝ **失敗しないのではなく、実行されていない**（しかも実行されないこと自体が
    # run ごとに変わるので、omission 数を目印にもできない）。
    #
    # ⚠ **開発機の実エントリを見に行かない。**`Entry.dataset.all` から条件に合う
    # エントリを `find` する作りだと、当たるかどうかが開発機ごとに変わり、
    # **assertion が 1 つも走らないまま緑になる**ケースが残る。
    # ⚠⚠ **衝突しにくい ID にする（#1612 の Codex P2）。**`clear_fixtures` は
    # この ID の行を無条件に消すので、**開発機に同名の実ソースがあると実データを
    # 消してしまう**（`bin/test.rb` は運用と同じ永続 DB を使う）。
    # ⚠ `__test_feed_source__` / `__test_source_run_log__` と同じ命名に揃える。
    FEED_ID = '__entry_fixture__'.freeze

    # ⚠ **1 件目はエンクロージャあり、2 件目は無し。**どちらの経路も必ず通す。
    # ⚠ `entry` テーブルの unique index は (feed, title, url) なので両方ずらす。
    FIXTURES = [
      {
        title: 'フィクスチャ 1（エンクロージャあり）',
        summary: 'エンクロージャを 2 件持つエントリ',
        url: 'https://feed.example.test/entries/1',
        enclosure_url: [
          'https://feed.example.test/pic/1.png',
          'https://feed.example.test/pic/2.png',
        ].to_json,
        extra_tags: ['fixture'].to_json,
      },
      {
        title: 'フィクスチャ 2（エンクロージャなし）',
        summary: 'エンクロージャを持たないエントリ',
        url: 'https://feed.example.test/entries/2',
        enclosure_url: [].to_json,
        extra_tags: [].to_json,
      },
    ].freeze

    def setup
      clear_fixtures
      @entries = FIXTURES.map do |values|
        Entry[Entry.insert(values.merge(feed: FEED_ID, published: Time.now))]
      end
    end

    # ⚠ **`super` を呼ぶ。**`TestCase#teardown` が `config.reload` と
    # `WebMock.reset!` を持っている。
    def teardown
      clear_fixtures
      super
    end

    # 🔴 **落ちた run の残骸も消す。**`setup` の手前でも消しておかないと、
    # teardown まで到達しなかった run の行が unique 制約に当たって
    # **次の run が丸ごと error になる**。
    def clear_fixtures
      Entry.where(feed: FEED_ID).delete
    end

    test 'フィクスチャのエントリが作られているか' do
      assert_equal(FIXTURES.size, @entries.size)
      assert_equal(FIXTURES.size, Entry.where(feed: FEED_ID).count)
    end

    def test_feed
      @entries.each do |entry|
        assert_kind_of(FeedSource, entry.feed)
        assert_equal(FEED_ID, entry.feed.id)
      end
    end

    def test_create_template
      @entries.each do |entry|
        assert_kind_of(Template, entry.create_template)
        assert_kind_of(Template, entry.create_template(:default))
      end
    end

    # #1473: 握り潰して nil を返すと FeedSource#fetch が `next` で読み飛ばし、
    # record_failure に到達せず run が no-op success になる
    def test_create_reraises_unexpected_error
      assert_raise(NoMethodError) do
        Entry.create(Object.new, FeedSource.all.first)
      end
    end

    def test_uri
      @entries.each do |entry|
        assert_kind_of(Ginseng::URI, entry.uri)
        assert_predicate(entry.uri, :absolute?)
      end
    end

    def test_enclosures
      with_enclosures, without_enclosures = @entries

      assert_equal(2, with_enclosures.enclosures.size)
      with_enclosures.enclosures.each do |uri|
        assert_kind_of(Ginseng::URI, uri)
        assert_predicate(uri, :absolute?)
      end
      assert_empty(without_enclosures.enclosures)
    end

    def test_tags
      # ⚠ ソース側の `dest/tags` と `extra_tags` が合流する。どちらも落とさない。
      # ⚠⚠ `TagContainer#create_tags` が返すのは **`#` 付きの表記**。素の 'test' で
      # 照合すると通らない（`disable?` を外して初めて分かった）。
      tags = @entries.first.tags

      assert_predicate(tags, :present?)
      tags.each {|tag| assert_kind_of(String, tag)}
      assert_include(tags, '#test')
      assert_include(tags, '#fixture')
    end
  end
end
