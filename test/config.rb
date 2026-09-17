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

    # 🔴 #1548: 公開は 1 手。⚠ **上のサンプリングでは窓を取りこぼしうる**ので、
    # 「公開の直前まで self が触られていないこと」を決定的に見る。
    # `super` が self を `update` する実装だと、この時点で `/sources` は
    # `application.yaml` の値（＝空）へ戻っている。
    def test_load_does_not_touch_self_until_publish
      write_sources(3)
      config.reload
      expected = config['/sources'].size
      seen = nil
      config.define_singleton_method(:replace) do |hash|
        seen = self['/sources'].size
        super(hash)
      end
      begin
        config.reload
      ensure
        config.singleton_class.remove_method(:replace)
      end

      assert_equal(expected, seen, '公開の前に self が書き換わっている')
      assert_equal(expected, config['/sources'].size)
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

    # 🔴 **テスト専用のソース定義が実際に読まれていること (#1593)。**
    #
    # ⚠⚠ `config/sources/` は git 管理外なので **CI にはソース定義が 1 件も無い**。
    # その状態では `Source.all do |source| ... end` の形のテストは**ブロックが 1 度も
    # 回らず、何も確かめずに緑になる**＝ **失敗しないのではなく実行されていない**。
    # 🔴 **ここが外れても「落ちない」ので、保証そのものにテストを置く。**
    def test_test_sources_are_loaded
      ids = Source.all.map(&:id)

      ['mastodon-dest', 'misskey-dest', 'line-dest', 'piefed-dest', 'webhook-dest'].each do |id|
        assert_include(ids, id, "test/sources/#{id}.yaml が読まれていない")
      end
    end

    # ⚠ **本番・開発では読まない。**`test/sources/` は検証用の宛先を持つので、
    # 運用の実行に混ざると**実在しないホストへ配信しようとする**。
    def test_test_sources_are_not_loaded_outside_test
      dirs = with_test_env(false) {Config.instance.send(:source_dirs)}

      assert_equal(1, dirs.size, dirs.inspect)
      assert_not_include(dirs.first, 'test/sources')
    end

    # 🔴 **#1596 の Codex P2: `TestCase.load` の時点で `test/sources/` が読まれていること。**
    #
    # ⚠⚠ `Config.instance` は `TEST` を立てる前に作られているので、読み直さないと
    # 最初のテストの teardown まで `test/sources/` が見えない＝ 単体実行で
    # `MastodonShriekerTest` などが `disable?` で omit される。
    def test_test_case_load_reads_test_sources
      saved = ENV.fetch('TEST', nil)
      ENV.delete('TEST')
      config.reload

      assert_not_include(source_ids, 'mastodon-dest', '前提: TEST が無ければ読まれない')

      TestCase.load('__no_such_case__')

      assert_include(source_ids, 'mastodon-dest')
    ensure
      ENV['TEST'] = saved
      config.reload
    end

    private

    # ⚠ 元の `Method` を保存して戻す（`remove_method` だと本物ごと消える）。
    def with_test_env(value)
      original = Environment.method(:test?)
      Environment.define_singleton_method(:test?) {value}
      return yield
    ensure
      Environment.define_singleton_method(:test?, original)
    end

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

    def source_ids
      return config['/sources'].map {|v| v['id']}
    end
  end
end
