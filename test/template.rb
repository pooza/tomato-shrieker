module TomatoShrieker
  class TemplateTest < TestCase
    def setup
      @source = TextSource.new({
        'id' => 'test-template-isolation',
        'source' => {'text' => 'body'},
        'dest' => {'hooks' => ['https://example.com/hook']},
      })
    end

    def test_create_template_returns_new_instance
      # memo 化した実体をそのまま返すと Parallel.each で壊し合う (#1474)
      assert_not_same(@source.create_template, @source.create_template)
    end

    def test_params_are_isolated
      a = @source.create_template
      b = @source.create_template
      a[:entry] = 'a'
      b[:entry] = 'b'

      assert_equal('a', a[:entry])
      assert_equal('b', b[:entry])
    end

    def test_templates_are_still_memoized
      # 複製元まで作り直すと ERB のコンパイルを毎回やり直すことになる
      assert_same(@source.templates[:default], @source.templates[:default])
    end

    def test_original_is_not_polluted
      original = @source.templates[:default]
      @source.create_template[:entry] = 'leaked'

      assert_nil(original[:entry])
    end

    def test_parallel_each_does_not_cross_contaminate
      # IcalendarSource#exec と同じ形。共有 Template だと別エントリの値が混ざる (#1474)
      entries = (1..50).map {|i| "entry-#{i}"}
      seen = Thread::Queue.new
      Parallel.each(entries, in_threads: 8) do |entry|
        template = @source.create_template
        template[:entry] = entry
        sleep(0.001)
        seen.push([entry, template[:entry]])
      end

      results = Array.new(seen.size) {seen.pop}

      assert_equal(entries.size, results.size)
      results.each {|expected, actual| assert_equal(expected, actual)}
    end
  end
end
