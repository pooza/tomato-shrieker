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

    # 🔴 #1560 / #1678 の Codex P2: 定義の更新時刻は、一覧と同時かそれより先に見えること。
    # ⚠ 後から書くと、公開の瞬間に来た要求は足したばかりのソースの期限を引けず 503 を返す。
    # ⚠ 消える定義の側も、公開の前に表から消えてはいけない（古い一覧にはまだ居る）。
    def test_load_publishes_definition_times_before_sources
      write_sources(1)
      config.reload
      removed = "#{PREFIX}0"
      added = "#{PREFIX}1"
      File.delete(source_path(0))
      File.write(source_path(1), {'source' => {'text' => 'new'}, 'schedule' => {'cron' => '0 0 * * *'}}.to_yaml)
      seen = nil
      config.define_singleton_method(:replace) do |hash|
        seen = [source_defined_at(added), source_defined_at(removed)]
        super(hash)
      end
      begin
        config.reload
      ensure
        config.singleton_class.remove_method(:replace)
      end

      assert_kind_of(Time, seen.first, '公開の時点で、足したソースの更新時刻が引けない')
      assert_kind_of(Time, seen.last, '公開の前に、消える定義の更新時刻が消えている')
      assert_kind_of(Time, config.source_defined_at(added))
      assert_nil(config.source_defined_at(removed), '公開の後も、消えた定義が残っている')
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

      # ⚠ `__entry_fixture__` は EntryTest がフィクスチャを紐づける先 (#1597)。
      ids_to_check = [
        'mastodon-dest',
        'misskey-dest',
        'line-dest',
        'piefed-dest',
        'webhook-dest',
        '__entry_fixture__',
      ]

      ids_to_check.each do |id|
        assert_include(ids, id, "test/sources/#{id}.yaml が読まれていない")
      end
    end

    # 🔴 **#1573: テストがソース定義を書く先は、リポジトリの外。**
    #
    # ⚠⚠ 実 `config/sources/` へ書くと、途中で SIGKILL されたときに `at_exit` も走らず、
    # `.gitignore` が `*` なので `git status` にも出ない。次の起動か `source reload` で
    # テスト用の定義が本番のスケジューラに登録される。
    def test_scratch_sources_dir_is_outside_repository
      dir = Config.scratch_sources_dir

      assert_false(File.expand_path(dir).start_with?(File.expand_path(Environment.dir)), dir)
      assert_true(File.directory?(dir))
      assert_include(Config.instance.send(:source_dirs), dir)
      assert_not_include(with_test_env(false) {Config.instance.send(:source_dirs)}, dir)
    end

    # 🔴 **#1573: テストの実行中に、実 `config/sources/` へ `__test_*` が置かれていないこと。**
    # ⚠ 置き場所を移し忘れたテストがあれば、ここか次の実行で見つかる。
    def test_no_test_definition_in_real_sources_dir
      leaked = Dir.glob(File.join(Environment.dir, 'config/sources', '__test_*'))

      assert_empty(leaked.map {|v| File.basename(v)})
    end

    # ⚠ 一時ディレクトリに置いた定義は、テスト時には読まれる。
    def test_scratch_sources_are_loaded
      path = File.join(Config.scratch_sources_dir, '__test_config_scratch__.yaml')
      File.write(path, {'source' => {'text' => 'x'}, 'dest' => {'tags' => ['test']}}.to_yaml)
      config.reload

      assert_include(source_ids, '__test_config_scratch__')
      assert_kind_of(Time, config.source_defined_at('__test_config_scratch__'))
    ensure
      FileUtils.rm_f(path)
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
      return File.join(Config.scratch_sources_dir, "#{PREFIX}#{key}.yaml")
    end

    def cleanup
      Dir.glob(File.join(Config.scratch_sources_dir, "#{PREFIX}*")).each do |f|
        File.delete(f)
      end
    end

    def source_ids
      return config['/sources'].map {|v| v['id']}
    end
  end
end
