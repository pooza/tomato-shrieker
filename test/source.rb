require 'rufus-scheduler'

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

    def test_mulukhiya?
      Source.all do |source|
        assert_boolean(source.mulukhiya?)
      end
    end

    def test_bot_account?
      Source.all do |source|
        assert_boolean(source.bot_account?)
        assert_boolean(source.bot?)
      end
    end

    def test_template_name
      Source.all do |source|
        assert_kind_of(String, source.template_name)
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

    def test_shriekers
      Source.all do |source|
        source.shriekers do |shrieker|
          assert_kind_of([MastodonShrieker, MisskeyShrieker, WebhookShrieker, LineShrieker], shrieker)
        end
      end
    end

    def test_mulukhiya
      Source.all do |source|
        next unless source.mulukhiya
        assert_kind_of(MulukhiyaService, source.mulukhiya)
      end
    end

    def test_tagging?
      Source.all do |source|
        assert_boolean(source.tagging?)
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
      Source.all do |source|
        next if source.prefix.nil?
        assert_kind_of(String, source.prefix)
      end
    end

    def test_post_at
      Source.all do |source|
        next if source.post_at.nil?
        assert_kind_of(String, source.post_at)
        assert_kind_of(String, source.at)
        assert(Rufus::Scheduler.parse(source.post_at).present?)
      end
    end

    def test_cron
      Source.all do |source|
        next if source.cron.nil?
        assert_kind_of(String, source.cron)
        assert(Rufus::Scheduler.parse(source.cron).present?)
      end
    end

    def test_period
      Source.all do |source|
        next if source.period.nil?
        assert_kind_of(String, source.period)
        assert_kind_of(String, source.every)
        assert(Rufus::Scheduler.parse(source.every).present?)
      end
    end
  end
end
