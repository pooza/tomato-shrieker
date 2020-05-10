require 'rufus-scheduler'

module TomatoToot
  class SourceTest < Test::Unit::TestCase
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

    def test_template
      Source.all do |source|
        assert_kind_of(String, source.template)
      end
    end

    def test_mastodon
      Source.all do |source|
        assert_boolean(source.mastodon?)
        next unless source.mastodon?
        assert_kind_of(Mastodon, source.mastodon)
      end
    end

    def test_webhooks
      Source.all do |source|
        source.webhooks.each do |webhook|
          assert_kind_of(Slack, webhook)
        end
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
