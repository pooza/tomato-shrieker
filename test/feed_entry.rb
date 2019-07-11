module TomatoToot
  class FeedEntryTest < Test::Unit::TestCase
    def test_tooted?
      Feed.all do |feed|
        feed.fetch do |entry|
          assert_false(entry.tooted?)
        end
      end
    end

    def test_date
      Feed.all do |feed|
        feed.fetch_all do |entry|
          assert(entry.date.is_a?(Time))
        end
      end
    end

    def test_body
      Feed.all do |feed|
        feed.fetch_all do |entry|
          assert(entry.body.present?)
          assert(entry.body.is_a?(String))
        end
      end
    end

    def test_enclosure
      Feed.all do |feed|
        feed.fetch_all do |entry|
          assert(entry.enclosure.is_a?(Ginseng::URI)) unless entry.enclosure.nil?
        end
      end
    end
  end
end
