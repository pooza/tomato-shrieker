module TomatoShrieker
  class WebhookShriekerTest < TestCase
    def disable?
      return true if Source.all.none? {|s| s.test? && s.webhook?}
      return super
    end

    def test_exec
      Source.all.select(&:test?).select(&:webhook?).each do |source|
        source.clear
        source.exec
      end
    end
  end
end
