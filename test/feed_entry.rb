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
          assert_kind_of(Time, entry.date)
        end
      end
    end

    def test_body
      Feed.all do |feed|
        feed.fetch_all do |entry|
          assert(entry.body.present?)
          assert_kind_of(String, entry.body)
        end
      end
    end

    def test_enclosure
      Feed.all do |feed|
        feed.fetch_all do |entry|
          next unless entry.enclosure
          assert_kind_of(Ginseng::URI, entry.enclosure)
        end
      end
    end
  end
end
