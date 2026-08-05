module TomatoShrieker
  class SourceTest < TestCase
    def test_all
      Source.all do |source|
        assert_kind_of(Source, source)
      end
    end

    def test_to_h
      Source.all do |source|
        assert_kind_of(Hash, source.to_h)
      end
    end

    def test_disable?
      Source.all do |source|
        assert_boolean(source.disable?)
      end
    end

    def test_mulukhiya?
      Source.all do |source|
        assert_boolean(source.mulukhiya?)
      end
    end

    def test_test?
      Source.all do |source|
        assert_boolean(source.test?)
      end
    end

    def test_bot?
      Source.all do |source|
        assert_boolean(source.bot?)
      end
    end

    def test_templates
      Source.all do |source|
        assert_kind_of(Hash, source.templates)
        assert_kind_of(Template, source.templates[:default])
      end
    end

    def test_create_template
      Source.all do |source|
        assert_kind_of(Template, source.create_template)
        assert_kind_of(Template, source.create_template(:default))
        # 呼ぶたびに別インスタンスでないと Parallel.each で壊し合う (#1474)
        assert_not_same(source.create_template, source.create_template)
      end
    end

    def test_dest_count
      Source.all do |source|
        assert_kind_of(Integer, source.dest_count)
        assert_operator(source.dest_count, :>=, 0)
        assert_equal(source.dest_count.positive?, source.dest?)
      end
    end

    def test_dest_count_counts_every_kind
      source = TextSource.new({
        'id' => 'test-dest-count',
        'source' => {'text' => 'body'},
        'dest' => {
          'hooks' => ['https://example.com/a', 'https://example.com/b'],
          'mastodon' => {'url' => 'https://example.com', 'token' => 't'},
        },
      })

      assert_equal(3, source.dest_count)
      assert_true(source.dest?)
    end

    # /status.json は全ソース分を毎回組み立てる。数えるだけで宛先へ接続してはいけない
    def test_dest_count_does_not_instantiate_shriekers
      source = TextSource.new({
        'id' => 'test-dest-count-piefed',
        'source' => {'text' => 'body'},
        'dest' => {
          'piefed' => {
            'host' => 'piefed.example.com', 'user_id' => 'u',
            'password' => 'p', 'community_id' => 1
          },
        },
      })

      assert_equal(1, source.dest_count)
      # piefed? を経由していれば PiefedShrieker#initialize の login で通信が起きる
      assert_nil(source.instance_variable_get(:@piefed))
    end

    # #1473: token を消したような半端な宛先を 1 と数えると、shriekers が 0 件なのに
    # dest? が真になり、塞いだはずの「永久に no-op success」がそのまま残る
    def test_dest_count_requires_complete_destination
      [
        ['mastodon', {'url' => 'https://example.com'}],
        ['misskey', {'url' => 'https://example.com'}],
        ['line', {'user_id' => 'u'}],
        ['piefed', {'host' => 'h', 'user_id' => 'u', 'password' => 'p'}],
        ['nostr', {'relays' => ['wss://example.com']}],
      ].each do |kind, incomplete|
        source = TextSource.new({
          'id' => "test-dest-incomplete-#{kind}",
          'source' => {'text' => 'body'},
          'dest' => {kind => incomplete},
        })

        assert_equal(0, source.dest_count, "#{kind} の不完全な設定を宛先として数えている")
        assert_false(source.dest?)
      end
    end

    # 必須キーが揃っていれば数える。DEST_KINDS が各アクセサのガード条件から
    # ずれていないことの担保（⚠ shriekers を呼ぶと piefed の login で通信するので使わない）
    def test_dest_count_accepts_complete_destination
      [
        ['mastodon', {'url' => 'https://example.com', 'token' => 't'}],
        ['misskey', {'url' => 'https://example.com', 'token' => 't'}],
        ['line', {'user_id' => 'u', 'token' => 't'}],
        ['piefed', {'host' => 'h', 'user_id' => 'u', 'password' => 'p', 'community_id' => 1}],
        ['nostr', {'private_key' => 'k'}],
      ].each do |kind, complete|
        source = TextSource.new({
          'id' => "test-dest-complete-#{kind}",
          'source' => {'text' => 'body'},
          'dest' => {kind => complete},
        })

        assert_equal(1, source.dest_count, "#{kind} の完全な設定を宛先として数えていない")
        assert_true(source.dest?)
      end
    end

    def test_dest_count_ignores_non_destination_keys
      source = TextSource.new({
        'id' => 'test-dest-count-empty',
        'source' => {'text' => 'body'},
        'dest' => {'tags' => ['a'], 'template' => 'common'},
      })

      assert_equal(0, source.dest_count)
      assert_false(source.dest?)
    end

    def test_spoiler_text
      Source.all do |source|
        assert_kind_of([String, NilClass], source.spoiler_text)
      end
    end

    def test_mastodon
      Source.all do |source|
        assert_boolean(source.mastodon?)
        next unless source.mastodon?

        assert_kind_of(MastodonShrieker, source.mastodon)
      end
    end

    def test_misskey
      Source.all do |source|
        assert_boolean(source.misskey?)
        next unless source.misskey?

        assert_kind_of(MisskeyShrieker, source.misskey)
      end
    end

    def test_line
      Source.all do |source|
        assert_boolean(source.line?)
        next unless source.line?

        assert_kind_of(LineShrieker, source.line)
      end
    end

    def test_piefed
      Source.all do |source|
        assert_boolean(source.piefed?)
        next unless source.piefed?

        assert_kind_of(PiefedShrieker, source.piefed)
      end
    end

    def test_shriekers
      Source.all do |source|
        source.shriekers do |shrieker|
          assert_kind_of([MastodonShrieker, MisskeyShrieker, WebhookShrieker, LineShrieker, PiefedShrieker, NostrShrieker], shrieker)
        end
      end
    end

    def test_mulukhiya
      Source.all do |source|
        next unless source.mulukhiya

        assert_kind_of(MulukhiyaService, source.mulukhiya)
      end
    end

    def test_remote_tagging?
      Source.all do |source|
        assert_boolean(source.remote_tagging?)
      end
    end

    def test_tags
      Source.all do |source|
        source.tags.each do |tag|
          assert_kind_of(String, tag)
        end
      end
    end

    def test_visibility
      Source.all do |source|
        assert_kind_of(String, source.visibility)
      end
    end

    def test_prefix
      Source.all.select(&:prefix).each do |source|
        assert_kind_of(String, source.prefix)
      end
    end

    def test_post_at
      Source.all.select(&:post_at).each do |source|
        assert_kind_of(String, source.post_at)
        assert_kind_of(String, source.at)
        assert_predicate(Rufus::Scheduler.parse(source.post_at), :present?)
      end
    end

    def test_cron
      Source.all.select(&:cron).each do |source|
        assert_kind_of(String, source.cron)
        assert_predicate(Rufus::Scheduler.parse(source.cron), :present?)
      end
    end

    def test_period
      Source.all.select(&:period).each do |source|
        assert_kind_of(String, source.period)
        assert_kind_of(String, source.every)
        assert_predicate(Rufus::Scheduler.parse(source.every), :present?)
      end
    end

    def test_monitored?
      Source.all.each do |source|
        assert_boolean(source.monitored?)
        assert_equal(source.post_at.nil?, source.monitored?)
      end
    end

    def test_next_run_at
      now = Time.now
      Source.all.each do |source|
        next_run = source.next_run_at(now)
        if source.post_at
          assert_nil(next_run)
        else
          assert_kind_of(Time, next_run)
          assert_operator(next_run, :>, now)
        end
      end
    end

    def test_monitor_grace_seconds
      Source.all.each do |source|
        grace = source.monitor_grace_seconds
        if source.post_at
          assert_nil(grace)
        else
          assert_kind_of(Integer, grace)
          assert_operator(grace, :>, 0)
        end
      end
    end

    # #1456: 配信エラーは渡された collector へ集約され、別インスタンス経由でも記録される。
    def test_shriek_collects_delivery_errors
      saved = ENV.fetch('TEST', nil)
      ENV.delete('TEST') # Environment.test? を false にし shrieker を実際に走らせる
      shrieker = Object.new
      def shrieker.exec(_params)
        raise('simulated delivery failure')
      end
      source = Source.new({'id' => 'test-delivery-collect'})
      source.define_singleton_method(:shriekers) do |&block|
        next enum_for(:shriekers) unless block
        block.call(shrieker)
      end
      stats = DeliveryStats.new
      source.shriek(template: nil, visibility: nil, stats:)

      assert_equal(1, stats.error_count)
      assert_equal(1, stats.attempted_count)
      assert_equal(0, stats.delivered_count)
      assert_kind_of(RuntimeError, stats.first_error)
      assert_nothing_raised do
        source.shriek(template: nil, visibility: nil, stats: nil)
      end
      assert_equal(1, stats.error_count)
    ensure
      ENV['TEST'] = saved
    end

    # #1433: 成功した配信も計上される。
    def test_shriek_counts_deliveries
      saved = ENV.fetch('TEST', nil)
      ENV.delete('TEST')
      shrieker = Object.new
      def shrieker.exec(_params)
        # 何もせず成功する shrieker
      end
      source = Source.new({'id' => 'test-delivery-count'})
      source.define_singleton_method(:shriekers) do |&block|
        next enum_for(:shriekers) unless block
        block.call(shrieker)
      end
      stats = DeliveryStats.new
      source.shriek(template: nil, visibility: nil, stats:)

      assert_equal(1, stats.attempted_count)
      assert_equal(1, stats.delivered_count)
      assert_false(stats.error?)
      assert_false(stats.noop?)
    ensure
      ENV['TEST'] = saved
    end

    # #1470: silence_tolerance は未指定なら検知しない (opt-in)。
    def test_monitor_silence_tolerance_seconds
      assert_nil(Source.new({'id' => 'test-silence-unset'}).monitor_silence_tolerance_seconds)
      source = Source.new({'id' => 'test-silence-str', 'monitor' => {'silence_tolerance' => '1d'}})

      assert_equal(86_400, source.monitor_silence_tolerance_seconds)
      source = Source.new({'id' => 'test-silence-int', 'monitor' => {'silence_tolerance' => 600}})

      assert_equal(600, source.monitor_silence_tolerance_seconds)
    end

    def test_silent?
      # しきい値未指定なら常に false
      source = Source.new({'id' => 'test-silent-unset'})
      source.define_singleton_method(:last_delivered_at_fallback) {Time.now - 86_400_000}

      assert_false(source.silent?)

      # 配信実績が無ければ断定しない
      source = Source.new({'id' => 'test-silent-unknown', 'monitor' => {'silence_tolerance' => '1d'}})

      assert_false(source.silent?)

      # しきい値を超えて沈黙していれば true
      source = Source.new({'id' => 'test-silent-stale', 'monitor' => {'silence_tolerance' => '1d'}})
      source.define_singleton_method(:last_delivered_at_fallback) {Time.now - 172_800}

      assert_true(source.silent?)
      assert_equal('fallback', source.last_delivered_at_origin)

      # しきい値内なら false
      source = Source.new({'id' => 'test-silent-fresh', 'monitor' => {'silence_tolerance' => '1d'}})
      source.define_singleton_method(:last_delivered_at_fallback) {Time.now - 60}

      assert_false(source.silent?)
    end

    def test_silent_boolean
      Source.all do |source|
        assert_boolean(source.silent?)
      end
    end

    def test_classes
      Source.classes.each do |source_class|
        assert_kind_of(Class, source_class[:class])
        assert_kind_of(String, source_class[:config])
      end
    end

    def test_create_tags
      source = TextSource.new('source' => {'text' => 'dummy'}, 'dest' => {'tags' => ['precure_fun']})
      tags = source.create_tags('dummy')

      assert_kind_of(Set, tags)
      assert_equal(Set['#precure_fun'], tags)
    end

    def test_create_tags_with_short_tag
      # 2文字以下のタグも素通しする (短タグフィルタはモロヘイヤ側責務)
      source = TextSource.new('source' => {'text' => 'dummy'}, 'dest' => {'tags' => ['実況', 'precure_fun']})

      assert_nothing_raised do
        tags = source.create_tags('dummy')

        assert_equal(Set['#実況', '#precure_fun'], tags)
      end
    end
  end
end
