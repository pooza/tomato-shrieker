require 'tmpdir'

module TomatoShrieker
  # CLI `source` のうち、ソース定義のファイルを読み書きするコマンド (#1463)。
  #
  # ⚠ **実 `config/sources/` には書かない。**`sources_dir` を一時ディレクトリへ差し替える
  # （#1573: テストが置いた定義を、稼働中の scheduler が reload で拾う経路がある）。
  class SourceCommandFileTest < TestCase
    ID = 'cli-file-test'.freeze
    # ⚠ `silence_tolerance` を入れてある。無いと `validate` は OK ではなく WARN を出す。
    BODY = [
      'source:', '  feed: https://example.com/feed',
      'dest:', '  hooks:', '    - https://example.com/x',
      'monitor:', '  silence_tolerance: 7d', ''
    ].join("\n").freeze

    def setup
      @dir = Dir.mktmpdir('tomato-shrieker-cli')
      dir = @dir
      @said = said = []
      @command = SourceCommand.new
      @command.define_singleton_method(:sources_dir) {dir}
      @command.define_singleton_method(:say) {|message = ''| said.push(message.to_s)}
      # ⚠ ガードが壊れていると `add` は $EDITOR を開いて CI が止まる。必ず潰しておく。
      @command.define_singleton_method(:open_editor) {|_path| nil}
    end

    def teardown
      FileUtils.rm_rf(@dir)
      super
    end

    # 🔴 **`disable` → `enable` で元の内容に戻り、`disable:` が二重にならないこと（`55839aa` の回帰）。**
    #
    # ⚠ `disable: false` を明記した定義へ `disable: true` を足すだけだと、YAML は後勝ちで
    # **止めたつもりなのに止まらない**。行単位で操作しているので、ヘッダ・コメント・
    # キー順が残ることも見る。
    def test_disable_and_enable_round_trip
      {
        'disable 無し' => BODY,
        'disable: true' => "disable: true\n#{BODY}",
        'disable: false' => "disable: false\n#{BODY}",
        '末尾に disable: false' => "#{BODY}disable: false\n",
        '--- ヘッダ' => "---\n#{BODY}",
        '--- ヘッダと disable: false' => "---\ndisable: false\n#{BODY}",
        '先頭コメント' => "# 説明のコメント\n#{BODY}",
        'コメントつきの disable' => "disable: false # いったん再開\n#{BODY}",
      }.each do |label, content|
        write(content)
        @command.disable(ID)

        assert_equal(1, top_level_disable_lines.size, "#{label}: disable が二重")
        assert_true(YAML.load_file(path)['disable'], "#{label}: 止まっていない")
        assert_equal(content.start_with?('---'), read.start_with?("---\n"), "#{label}: ヘッダ")
        @command.enable(ID)

        assert_empty(top_level_disable_lines, "#{label}: disable が残っている")
        assert_equal(content.lines.grep_v(/\Adisable\s*:/).join, read, "#{label}: 他の行が変わった")
      end
    end

    # ⚠ 何度止めても 1 行のまま。
    def test_disable_twice
      write(BODY)
      2.times {@command.disable(ID)}

      assert_equal(["disable: true\n"], top_level_disable_lines)
    end

    # ⚠ 入れ子の `disable:`（インデントあり）と、`disable` で始まる別のキーには触らない。
    def test_disable_keeps_nested_keys
      content = "#{BODY}keep:\n  disable: false\ndisabled_note: true\n"
      write(content)
      @command.disable(ID)
      @command.enable(ID)

      assert_equal(content, read)
    end

    # ⚠ 既に有効な定義への `enable` は、ファイルを書き換えない（reload の案内も出さない）。
    def test_enable_already_enabled
      write(BODY)
      mtime = File.mtime(path)
      @command.enable(ID)

      assert_equal(["already enabled: #{ID}"], @said)
      assert_equal(BODY, read)
      assert_equal(mtime, File.mtime(path))
    end

    def test_disable_reports_and_hints_reload
      write(BODY)
      @command.disable(ID)

      assert_equal("disabled: #{ID}", @said.first)
      assert_include(@said.last, 'source reload')
    end

    def test_disable_unknown_source
      error = assert_raise(Thor::Error) {@command.disable('no-such-source')}

      assert_equal('source not found: no-such-source', error.message)
    end

    # 🔴 **全件の `validate` は、YAML として壊れたファイルがあっても止まらないこと（`55839aa`）。**
    #
    # ⚠ 壊れた 1 件で例外のまま抜けると、後ろの定義は 1 件も検査されない。壊れたファイルは
    # NG に数え、最後に件数つきで失敗する（`exit` ではなく `Thor::Error`）。
    def test_validate_continues_after_broken_yaml
      write("source:\n  feed: [unclosed\n", 'a-broken')
      write("source:\n  feed: not a uri\ndest:\n  hooks:\n    - https://example.com/x\n", 'b-invalid')
      write(BODY, 'c-valid')
      error = assert_raise(Thor::Error) {@command.validate}
      said = @said.join("\n")

      assert_equal('2 source(s) invalid', error.message)
      assert_include(said, "NG\ta-broken")
      assert_include(said, 'YAML 構文エラー')
      assert_include(said, "NG\tb-invalid")
      assert_include(said, "OK\tc-valid")
    end

    # ⚠ WARN はスキーマ上は妥当な定義への指摘なので、失敗に数えない (#1470)。
    def test_validate_warning_is_not_failure
      write("source:\n  feed: https://example.com/feed\ndest:\n  hooks:\n    - https://example.com/x\n")
      @command.validate

      assert_equal("WARN\t#{ID}", @said.first)
      assert_include(@said.last, 'silence_tolerance')
    end

    def test_validate_all_valid
      write(BODY, 'a')
      write(BODY, 'b', 'yml')
      @command.validate

      assert_equal(["OK\ta", "OK\tb"], @said.sort)
    end

    # ⚠ ID を指定したら、その 1 件だけを見る（他の壊れた定義に引きずられない）。
    def test_validate_single
      write("source:\n  feed: [unclosed\n", 'a-broken')
      write(BODY, 'c-valid')
      @command.validate('c-valid')

      assert_equal(["OK\tc-valid"], @said)
      assert_raise(Thor::Error) {@command.validate('a-broken')}
      assert_raise(Thor::Error) {@command.validate('no-such-source')}
    end

    # 🔴 **`add` は、ディレクトリの外へ出る id を弾くこと（`55839aa`）。**
    # ⚠ id はそのままファイル名になる。`../x` を通すと `config/sources/` の外へ書ける。
    def test_add_rejects_invalid_id
      @command.options = {class: 'feed'}
      ['../evil', 'a/b', 'a b', '', "a\nb", '/etc/x', 'a;b'].each do |id|
        error = assert_raise(Thor::Error, id.inspect) {@command.add(id)}

        assert_include(error.message, 'invalid id')
      end
      assert_empty(Dir.children(@dir))
      assert_false(File.exist?(File.join(File.dirname(@dir), 'evil.yaml')))
    end

    def test_add_rejects_unknown_class
      @command.options = {class: 'nope'}
      error = assert_raise(Thor::Error) {@command.add(ID)}

      assert_include(error.message, 'unknown class: nope')
      assert_empty(Dir.children(@dir))
    end

    # ⚠ 雛形はどの種別も YAML として読め、判別キーを持つ（どのクラスにもならない雛形を作らない）。
    def test_add_writes_template_for_every_class
      SourceTemplates::ALL.each_key do |name|
        @command.options = {class: name}
        @command.add("#{ID}-#{name}")
        params = YAML.load_file(path("#{ID}-#{name}"))

        assert_kind_of(Hash, params, name)
        assert_true(Source.matched?(params), "#{name}: 判別キーが無い")
      end
    end

    def test_add_rejects_existing_id
      write(BODY)
      @command.options = {class: 'feed'}
      error = assert_raise(Thor::Error) {@command.add(ID)}

      assert_equal("source already exists: #{ID}", error.message)
      assert_equal(BODY, read)
    end

    # CLI の入口（Thor の登録）。⚠ コマンドを足したのに登録が漏れる・名前が変わるのを受ける。
    def test_commands_are_registered
      expected = [
        'list', 'status', 'collisions', 'fetch', 'shriek', 'touch', 'clear', 'add', 'edit',
        'delete', 'disable', 'enable', 'ack', 'reload', 'validate'
      ]

      assert_equal(expected.sort, (SourceCommand.all_commands.keys - ['help', 'tree']).sort)
      assert_equal(SourceCommand, MainCommand.subcommand_classes['source'])
      assert_true(MainCommand.exit_on_failure?)
    end

    # ⚠ **入口から通す。**`bin/shrieker source list` と同じ道（`MainCommand.start`）。
    # 失敗する呼び方はここでは試さない（`exit_on_failure?` が真なので `exit` が呼ばれ、
    # 残りのテストが走らないまま緑で終わる＝ #1668）。
    def test_start_source_list
      output = capture_stdout {MainCommand.start(['source', 'list'])}

      assert_include(output.lines.map(&:chomp), "command\tCommandSource")
    end

    private

    def path(id = ID, suffix = 'yaml')
      return File.join(@dir, "#{id}.#{suffix}")
    end

    def write(content, id = ID, suffix = 'yaml')
      File.write(path(id, suffix), content)
    end

    def read(id = ID)
      return File.read(path(id))
    end

    def top_level_disable_lines
      return File.readlines(path).grep(/\Adisable\s*:/)
    end

    def capture_stdout
      original = $stdout
      $stdout = StringIO.new
      yield
      return $stdout.string
    ensure
      $stdout = original
    end
  end
end
