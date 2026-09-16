require 'webmock'

module TomatoShrieker
  class TestCase < Ginseng::TestCase
    include Package
    include WebMock::API

    # ソースの種類ごとに返すフィクスチャ。⚠ 判定はクラス名の文字列ではなく実体の `is_a?`
    # （サブクラスも拾う）。
    FEED_FIXTURES = {
      'YouTubeChannelSource' => 'youtube.xml',
      'GoogleNewsSource' => 'google_news.rss',
      'GitHubRepositorySource' => 'github.atom',
      'IcalendarSource' => 'calendar.ics',
    }.freeze
    DEFAULT_FEED_FIXTURE = 'feed.rss'.freeze

    # 🔴 **`require` だけでは有効にならない (#1468)。**`WebMock.enable!` を呼ぶまで
    # `stub_request` も `disable_net_connect!` も**無言で素通りする**。⚠⚠ 書いたつもりで
    # 書けていない状態と、そもそも書いていない状態が、テスト結果から区別できない。
    #
    # ⚠⚠ **`def setup` ではなくコールバックで登録する。**メソッドにすると、サブクラスが
    # `setup` を定義して `super` を忘れた瞬間に外れ、**外れても落ちない**ので気付けない
    # （現に `test/entry.rb` / `test/source_run_log.rb` は `def setup` を持つ）。
    #
    # ⚠ **テストごとに張り直す。**個別のケースが teardown で `WebMock.disable!` しても、
    # 次のテストの手前で必ず戻る（**順序に依存して保護が外れる**のを防ぐ）。
    setup do
      WebMock.enable!
      WebMock.disable_net_connect!
      stub_default_feeds
    end

    # ⚠ **手元の `config/sources/*.yaml` は実サービスを指している**（GitHub / YouTube /
    # Google カレンダー / google-news-rss-cleaner）。⚠⚠ `config/sources` は git 管理外で
    # **開発機ごとに中身が違う**ため、**URL を列挙しても網羅できない。種類ごとに
    # パターンで塞ぐ。**
    #
    # ⚠ テスト側で `stub_request` を書けば**後勝ちで上書きできる**
    # （WebMock は最後に登録した stub から見る）。
    def stub_default_feeds
      stub_known_services
      stub_configured_sources
    end

    # ⚠ **手元の `config/sources/*.yaml` は実サービスを指している**（GitHub / YouTube /
    # Google カレンダー / google-news-rss-cleaner）。種類ごとにパターンで塞ぐ。
    def stub_known_services
      stub_request(:get, %r{//www\.youtube\.com/feeds/videos\.xml})
        .to_return(status: 200, body: fixture('youtube.xml'))
      stub_request(:get, %r{//github\.com/.+\.atom})
        .to_return(status: 200, body: fixture('github.atom'))
      stub_request(:get, %r{//news\.google\.com/rss/})
        .to_return(status: 200, body: fixture('google_news.rss'))
      stub_request(:get, %r{/clean(\?|\z)})
        .to_return(status: 200, body: fixture('google_news.rss'))
      stub_request(:get, /\.ics(\?|\z)/)
        .to_return(status: 200, body: calendar_fixture)
    end

    # 🔴 **設定済みソースの「実際の取得先」を 1 件ずつ塞ぐ（#1468 の Codex P2）。**
    #
    # ⚠⚠ サービス別のパターンだけでは、**汎用の `source/feed` や `source/url` を持つ
    # ソースが漏れる**。`config/sources` は git 管理外で開発機ごとに中身が違うので、
    # **「どんな URL が入っていても塞がる」ようにしておかないと、その開発機でだけ
    # `rake test` が落ちる**。
    #
    # ⚠ 上のパターンより**後に**登録する（WebMock は後勝ち）＝ より具体的なこちらが勝つ。
    # ⚠ 1 件の失敗で全体を止めない。`uri` は設定次第で nil も例外もありうる。
    def stub_configured_sources
      Source.all do |source|
        stub_source_feed(source)
      rescue StandardError
        next
      end
    rescue StandardError
      nil
    end

    def stub_source_feed(source)
      return unless source.respond_to?(:uri)
      return unless uri = source.uri
      # ⚠ `IcalendarSource#uri` は毎回 `?t=<時刻>` を付けるので、クエリを落として前方一致。
      base = uri.to_s.sub(/\?.*\z/, '')
      return if base.empty?
      # ⚠⚠ **本文を先に組んでから登録する。**`stub_request(...).to_return(...)` の順だと、
      # 本文の組み立てで例外が出たときに**「応答を定義していない stub」だけが残り、
      # 空ボディの 200 を返す**（＝ パーサが「No valid parser for XML」で落ちる）。
      # 呼び出し側の `rescue` が握るので、**気付けないまま全件が空になる**。
      body = feed_fixture_for(source)
      stub_request(:get, /\A#{Regexp.escape(base)}/).to_return(status: 200, body:)
    end

    def feed_fixture_for(source)
      name = FEED_FIXTURES.find {|klass, _| source.is_a?(TomatoShrieker.const_get(klass))}&.last
      return calendar_fixture if name == 'calendar.ics'
      return fixture(name || DEFAULT_FEED_FIXTURE)
    end

    def fixture(name)
      return File.read(File.join(self.class.dir, 'fixtures', name))
    end

    # 🔴 **`calendar.ics` の日付は実行時に埋める。**`test-ical-schedule.yaml` は
    # `days: 7` で絞るので、固定日付にすると**フィクスチャが古びた日から `entries` が
    # 恒久的に空になり、テストが何も確かめなくなる**（しかも緑のまま）。
    def calendar_fixture
      base = Time.now.utc
      body = fixture('calendar.ics')
      # ⚠ `test-ical-schedule.yaml` の `days: 7` に収める。5 件とも「今日から 5 日以内」。
      (1..5).each do |i|
        start = base + (i * 86_400) - 43_200
        body = body
          .gsub("__START#{i}__", start.strftime('%Y%m%dT%H%M%SZ'))
          .gsub("__END#{i}__", (start + 3_600).strftime('%Y%m%dT%H%M%SZ'))
      end
      return body
    end

    def teardown
      config.reload
      WebMock.reset!
    end

    def self.load(cases = nil)
      ENV['TEST'] = Package.full_name
      names(cases).each do |name|
        puts "+ case: #{name}" if Environment.test?
        require File.join(dir, "#{name}.rb")
      rescue => e
        puts "- case: #{name} (#{e.message})" if Environment.test?
      end
    end

    def self.names(cases = nil)
      if cases
        names = cases.split(',')
          .map {|v| [v, "#{v}Test", v.underscore, "#{v.underscore}_test"]}.flatten
          .select {|v| File.exist?(File.join(dir, "#{v}.rb"))}.compact
      else
        finder = Ginseng::FileFinder.new
        finder.dir = dir
        finder.patterns.push('*.rb')
        names = finder.exec.map {|v| File.basename(v, '.rb')}
      end
      return names.to_set
    end

    def self.dir
      return File.join(Environment.dir, 'test')
    end
  end
end
