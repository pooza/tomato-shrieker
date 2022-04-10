module TomatoShrieker
  class MastodonShriekerTest < TestCase
    def test_exec
      Source.all.select(&:test?).select(&:mastodon).each do |source|
        source.clear
        source.exec
      end
    end
  end
end
