module TomatoShrieker
  class EntryTest < TestCase
    def disable?
      return true if Entry.dataset.empty?
      return super
    end

    def setup
      @entries = Entry.dataset.all.select(&:feed)
    end

    test '1レコード以上のエントリが存在するか' do
      assert_predicate(@entries, :present?)
    end

    def test_feed
      assert_kind_of(FeedSource, @entries.sample.feed) if @entries.present?
    end

    def test_create_template
      return unless entry = @entries.find(&:create_template)

      assert_kind_of(Template, entry.create_template)
      assert_kind_of(Template, entry.create_template(:default))
    end

    def test_uri
      return unless entry = @entries.find(&:uri)

      assert_kind_of(Ginseng::URI, entry.uri)
    end

    def test_enclosures
      return unless entry = @entries.find(&:enclosures)

      assert_kind_of(Array, entry.enclosures)
      entry.enclosures.each do |uri|
        assert_kind_of(Ginseng::URI, uri)
      end
    end

    def test_shriekable?
      return false unless entry = @entries.first

      assert_boolean(entry.shriekable?)
    end

    def test_tags
      return unless entry = @entries.find {|v| v.tags.any?}

      entry.tags.each do |tag|
        assert_kind_of(String, tag)
      end
    end
  end
end
