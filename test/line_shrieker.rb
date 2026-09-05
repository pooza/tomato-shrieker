module TomatoShrieker
  class LineShriekerTest < TestCase
    def disable?
      return true if Source.all.none? {|s| s.test? && s.line?}
      return super
    end

    def test_exec
      Source.all.select(&:test?).select(&:line).each do |source|
        source.clear
        assert_nothing_raised {source.exec}
      end
    end

    def test_templates
      Source.all.select(&:test?).select(&:line).each do |source|
        assert_kind_of(Hash, source.templates)
        assert_kind_of(Template, source.templates[:default])
      end
    end
  end

  # ⚠ **`LineShriekerTest` とは別クラスにする。**あちらは `disable?` で
  # 「test 用の LINE ソースが無ければケースごと省略」する（#1520）ので、
  # **設定の壊れ方を見るテストが本番設定の有無に左右されてしまう。**
  class LineShriekerConfigTest < TestCase
    # 🔴 **初期化に失敗しても Shrieker は作れること (#1473)。**
    # ⚠ ここで落とすと `shriekers` からこの宛先が消え、「設定はあるのに宛先ゼロ」に
    # なって #1504 の計上が崩れる。
    def test_new_survives_broken_config
      with_broken_line_config do
        assert_nothing_raised {LineShrieker.new({id: 'u', token: 't'})}
      end
    end

    # 🔴 **exec には真因がそのまま出ること (#1487)。**
    #
    # ⚠⚠ 以前は初期化失敗を握って続行していたので `@http.base_uri` が未設定のまま
    # 残り、`say` が `NoMethodError: undefined method 'prefix' for nil` で落ちていた。
    # **run_log と `/healthz` に出るのは真因の `Ginseng::ConfigError` ではなく症状の
    # `NoMethodError`** で、運用者は原因にたどり着けない。
    def test_exec_raises_initialization_error
      with_broken_line_config do
        shrieker = LineShrieker.new({id: 'u', token: 't'})
        error = assert_raise_kind_of(StandardError) {shrieker.exec({template: 'x'})}

        assert_kind_of(Ginseng::ConfigError, error, '症状ではなく真因を出すこと')
      end
    end

    private

    # `Ginseng::LineService#initialize` が落ちるのは `/line/urls/api` の欠落時だけ。
    #
    # ⚠ **`raw` の鍵は設定ファイルの basename**（`local` / `application` / `lib` /
    # hostname）で、優先順は `Config#basenames` の順。低い側へ書いても高い側の値に
    # 上書きされるので、**実在するうちいちばん強い basename** を差し替える。
    def with_broken_line_config
      key = config.basenames.find {|v| config.raw.key?(v)}
      original = config.raw[key]['line']
      config.raw[key]['line'] = (original || {}).deep_dup.tap {|v| v.delete('urls')}
      config.reload
      yield
    ensure
      config.raw[key]['line'] = original
      config.reload
    end
  end
end
