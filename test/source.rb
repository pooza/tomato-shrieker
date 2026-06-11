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
      end
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
