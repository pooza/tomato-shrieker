module TomatoShrieker
  class ConfigTest < TestCase
    # ⚠ 実在のソースと衝突しない接頭辞。後始末に失敗しても見分けがつくようにする。
    PREFIX = '__test_config_atomic__'.freeze

    def teardown
      cleanup
      super
    end

    def test_secure_dump
      assert_kind_of(Array, config.secure_dump)
    end

    # #1530: reload の途中経過が外から見えないこと。
    #
    # 🔴 以前は `self['/sources']` へ 1 件ずつ push していたので、push の間だけ
    # 一覧が短かった。⚠ `/status.json` は全ソースを舐めるので約 900ms かかり
    # (#1472)、この窓に重なると**ソースが欠けて見える**。`/healthz/source/:id` は
    # 404 を返し、Kuma に偽の 404 / 503 が出る。
    def test_load_never_exposes_partial_sources
      write_sources(5)
      config.reload
      expected = config['/sources'].size
      observed = []
      reader = Thread.new do
        observed.push(config['/sources'].size) while Thread.current[:run] != false
      end
      reader[:run] = true
      10.times {config.reload}
      reader[:run] = false
      reader.join(5)

      assert_operator(observed.size, :>, 0, '読み手が 1 度も観測できていない')
      assert_equal([expected], observed.uniq, "reload の途中経過が見えている: #{observed.uniq.sort}")
    end

    # 🔴 #1530: 壊れた YAML があっても、それまでの内容を壊さないこと。
    #
    # 以前は 3 件目で raise すると 2 件目まで積まれた状態で残った。⚠ ソース定義を
    # 手で 1 文字打ち間違えただけで、稼働中のソース一覧が壊れた。
    def test_load_keeps_previous_sources_when_yaml_is_broken
      write_sources(3)
      config.reload
      before = config['/sources'].size

      File.write(source_path('broken'), "source:\n  feed: [unclosed\n")

      assert_raise_kind_of(StandardError) {config.reload}
      assert_equal(before, config['/sources'].size, '壊れた YAML で一覧が欠けている')
    end

    private

    def write_sources(count)
      count.times do |i|
        File.write(source_path(i), {
          'source' => {'text' => "test #{i}"},
          'schedule' => {'cron' => '0 0 * * *'},
          'dest' => {'tags' => ['test']},
        }.to_yaml)
      end
    end

    def source_path(key)
      return File.join(Environment.dir, 'config/sources', "#{PREFIX}#{key}.yaml")
    end

    def cleanup
      Dir.glob(File.join(Environment.dir, 'config/sources', "#{PREFIX}*")).each do |f|
        File.delete(f)
      end
    end
  end
end
