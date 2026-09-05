module TomatoShrieker
  class FeedSourceTest < TestCase
    FIXTURE_ID = '__test_feed_source__'.freeze
    SENTRY_STUBBED = [:initialized?, :capture_exception].freeze

    def test_all
      assert_kind_of(Enumerator, FeedSource.all)
    end

    def test_feedjira
      FeedSource.all do |source|
        classes = [
          Feedjira::Parser::Atom,
          Feedjira::Parser::RSS,
          Feedjira::Parser::AtomYoutube,
          Feedjira::Parser::ITunesRSS,
        ]

        assert_kind_of(classes, source.feedjira)
      end
    end

    def test_enclosure?
      FeedSource.all do |source|
        assert_boolean(source.enclosure?)
      end
    end

    def test_category
      FeedSource.all.select(&:category).each do |source|
        assert_kind_of(String, source.category)
      end
    end

    def test_keyword
      FeedSource.all.select(&:keyword).each do |source|
        assert_kind_of(Regexp, source.keyword)
      end
    end

    def test_negative_keyword
      FeedSource.all.select(&:negative_keyword).each do |source|
        assert_kind_of(Regexp, source.negative_keyword)
      end
    end

    def test_time
      FeedSource.all.select(&:touched?).each do |source|
        assert_kind_of(Time, source.time)
      end
    end

    def test_touched?
      FeedSource.all do |source|
        assert_boolean(source.touched?)
      end
    end

    def test_entries
      FeedSource.all do |source|
        assert_kind_of(Enumerator, source.entries)
        assert_predicate(source.entries.count, :positive?)
        source.entries.first(5).each do |entry|
          classes = [
            Feedjira::Parser::AtomEntry,
            Feedjira::Parser::RSSEntry,
            Feedjira::Parser::AtomYoutubeEntry,
            Feedjira::Parser::ITunesRSSItem,
          ]

          assert_kind_of(classes, entry)
        end
      end
    end

    def test_present?
      FeedSource.all do |source|
        assert_boolean(source.present?)
      end
    end

    def test_uri
      FeedSource.all do |source|
        assert_kind_of(Ginseng::URI, source.uri)
      end
    end

    def test_prefix
      FeedSource.all do |source|
        assert_kind_of(String, source.prefix)
      end
    end

    # 🔴 **`shrieker_errors` のキーをクラス名に依存させない (#1485)。**
    # 以前は `"#{self.class}#fetch"` だったのでサブクラスごとにキーが増え、宛先別の
    # 分布（`MastodonShrieker` 等）と同じ Hash に足し込まれて `/status.json` が
    # 読めなくなっていた。
    def test_fetch_failure_kind_is_not_class_dependent
      stats = DeliveryStats.new
      [FeedSource, Class.new(FeedSource)].each {|klass| run_failing_fetch(klass, stats)}

      assert_equal({'source#fetch' => 2}, stats.shrieker_errors,
        'サブクラスごとにキーが増えている')
    end

    # 🔴 **`/healthz` を 503 にするのに Sentry へ出ないエラーを作らない (#1485)。**
    # 既存の失敗チャンネル（`Source#shriek` の shrieker 失敗、run 全体の例外）は
    # 送っているのに、4.5.0 で新設したこの経路だけ送っていなかった。
    def test_fetch_failure_is_captured_by_sentry
      captured = []
      with_sentry_stub(captured) {run_failing_fetch(FeedSource, DeliveryStats.new)}

      assert_equal(1, captured.size, '503 になるのに Sentry へ出ていない')
      assert_equal('fetch', captured.first[:tags][:stage])
      assert_equal(FIXTURE_ID, captured.first[:tags][:source])
    end

    # ⚠⚠ **報告より先に計上する (#1485)。**この rescue で `/healthz` を赤にできるのは
    # run_log への計上だけ。報告（logger）を先に打つと、壊れた例外メッセージ
    # （#1469 の族）でそこが落ちたときに **run が no-op success に戻る**
    # ＝ #1473 が塞いだ穴が開き直す。
    def test_fetch_failure_is_recorded_before_reporting
      stats = DeliveryStats.new
      source = stub_failing(FeedSource.new(fixture_params), stats)
      source.define_singleton_method(:logger) {raise 'logger boom'}
      begin
        source.fetch {|_record| nil}
      rescue StandardError
        nil
      end

      assert_equal({'source#fetch' => 1}, stats.shrieker_errors,
        '報告が落ちると計上まで落ちている')
    end

    private

    def fixture_params
      return {'id' => FIXTURE_ID, 'source' => {'feed' => 'https://example.com/f.rss'}}
    end

    def run_failing_fetch(klass, stats)
      stub_failing(klass.new(fixture_params), stats).fetch {|_record| nil}
    end

    # ⚠ ネットワークへ出ない。`entries` と `create_record` を差し替えて、
    # 「配信手前でエントリが落ちる」経路だけを通す。
    def stub_failing(source, stats)
      source.define_singleton_method(:entries) {|&block| block ? [:entry].each(&block) : [:entry].each}
      source.define_singleton_method(:ignore_entry?) {|_entry| false}
      source.define_singleton_method(:create_record) {|_entry| raise 'boom'}
      source.instance_variable_set(:@delivery_stats, stats)
      return source
    end

    # ⚠⚠ **`remove_method` で戻してはいけない。**`Sentry.initialized?` は Sentry 自身の
    # singleton class に生えているので、`define_singleton_method` は**本物を上書き**する。
    # `remove_method` すると本物ごと消えて、**以降のテストが軒並み
    # `NoMethodError: undefined method 'initialized?'` で落ちる**（実際に踏んだ）。
    # 元の Method を保存して差し戻す。
    def with_sentry_stub(captured)
      originals = SENTRY_STUBBED.to_h {|name| [name, Sentry.method(name)]}
      Sentry.define_singleton_method(:initialized?) {true}
      Sentry.define_singleton_method(:capture_exception) do |error, **options|
        captured.push({error:}.merge(options))
      end
      yield
    ensure
      originals&.each {|name, method| Sentry.define_singleton_method(name, method)}
    end
  end
end
