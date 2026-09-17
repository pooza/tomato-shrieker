module TomatoShrieker
  class SourceCommandTest < TestCase
    ACK_ID = '__test_source_command_ack__'.freeze
    ADD_ID = '__test_source_command_add__'.freeze

    # teardown は異常終了で走らない。config/sources/.gitignore が `*` なので
    # 取り残しは git status にも出ず、次のスケジューラ起動で偽ソースとして登録される。
    at_exit do
      Dir.glob(File.join(Environment.dir, 'config/sources', '__test_source_command*'))
        .each {|f| FileUtils.rm_f(f)}
    end

    def setup
      @command = SourceCommand.new
    end

    # #1513: silence_tolerance の表示が整数除算で「0日」にならないこと。
    #
    # ⚠ スキーマは `12h` / `30m` を許すので (`^((\d+(\.\d+)?[smhdwMy])+|\d+(\.\d+)?)$`)、
    # 日未満のソースでは「次に silence_tolerance (0日) を超えたら」と出ていた。
    # ⚠ #1496 の「9 月上旬に 7d → 3d へ締める」運用で日未満を入れたら踏む。
    def test_tolerance_label
      {
        7_776_000 => '90日',
        259_200 => '3日',
        129_600 => '36時間',
        43_200 => '12時間',
        1_800 => '30分',
        45 => '45秒',
      }.each do |seconds, expected|
        assert_equal(expected, @command.send(:tolerance_label, stub_source(seconds)))
      end
    end

    # 🔴 **#1506: `ack` が未達にも効くこと、そしてそれを出力で言うこと。**
    #
    # ⚠ 以前は `SilenceAck` を書くだけで `undelivered` には一切効かないのに、出力は
    # 「確認済みにしました」とだけ返していた。**運用者は緑に戻ると期待して Kuma の
    # 赤を放置する。**
    def test_ack_reports_undelivered
      said = ack_with(stub_source(nil, undelivered: true))

      assert_include(said, 'undelivered')
      assert_not_nil(SilenceAck.acknowledged_at(ACK_ID), '確認が記録されていない')
    ensure
      SilenceAck.where(source_id: ACK_ID).delete
    end

    # ⚠ 効いていない範囲を「確認済み」と言わない。silence_tolerance 未設定なら
    # その行は出さない。
    def test_ack_does_not_mention_silence_without_tolerance
      said = ack_with(stub_source(nil, undelivered: true))

      assert_not_include(said, 'silence_tolerance')
    ensure
      SilenceAck.where(source_id: ACK_ID).delete
    end

    # 確認するものが無ければ記録しない
    def test_ack_refuses_when_nothing_to_acknowledge
      said = ack_with(stub_source(nil, undelivered: false))

      assert_include(said, '確認するものがありません')
      assert_nil(SilenceAck.acknowledged_at(ACK_ID))
    ensure
      SilenceAck.where(source_id: ACK_ID).delete
    end

    # 🔴 **#1571: `<id>.yml` があるときに `<id>.yaml` を作らせないこと。**
    #
    # ⚠ 読み込みは `*.{yaml,yml}` の両方なので、`.yaml` の存在だけで判定していると
    # **同じ id の定義を 2 つ作れる**。そうなると `Source.create` は先頭しか返さず、
    # `/healthz/source/:id` は片方を見ないまま緑になる。
    def test_add_rejects_duplicate_id_in_other_suffix
      File.write(source_path(ADD_ID, 'yml'), "source:\n  feed: https://example.com/x\n")
      # ⚠ ガードが壊れていると `add` は $EDITOR を開いて CI が止まる。必ず潰しておく。
      @command.define_singleton_method(:edit_and_validate) {|_id, _path| nil}
      @command.options = {class: 'feed'}

      error = assert_raise(Thor::Error) {@command.add(ADD_ID)}

      # ⚠ options 未設定による "unknown class" で通ってしまわないよう、理由まで見る。
      assert_include(error.message, 'already exists')
      assert_false(File.exist?(source_path(ADD_ID, 'yaml')), '重複した定義が作られている')
    ensure
      ['yml', 'yaml'].each {|suffix| FileUtils.rm_f(source_path(ADD_ID, suffix))}
    end

    # 🔴 **#1570: 起動なら倒れる定義が残っているうちは HUP を送らないこと。**
    #
    # ⚠ 反映できずに終わるのは不便だが、**壊れた YAML をディスクに残したまま
    # reload が成功すると、次のデプロイ / 再起動 / OOM で全ソースが止まる**。
    # 2026-09-05 に本番で 7 回の再起動・約 50 秒の全停止が起きている。
    def test_reload_refuses_unstartable_source
      said = []
      @command.define_singleton_method(:say) {|message| said.push(message)}
      @command.define_singleton_method(:unstartable_sources) do
        [['broken-source', ['/schedule/cron: invalid cron string "17,47 CLAUDE.md"']]]
      end

      # ⚠ **HUP を送る手前で止まることまで見る。**メッセージだけ増やして送っていたら
      # この issue は直っていない。daemon を組み立てもしないことで確かめる。
      assert_raise(Thor::Error) {with_daemon_guard {@command.reload}}
      assert_include(said.join("\n"), '/schedule/cron:')
      assert_include(said.join("\n"), 'broken-source')
    end

    # ⚠ **スキーマ違反では止めないこと。**起動はスキーマを見ないので、ここで全 NG を
    # 止めると「起動はできるのに reload は拒否される」定義が生まれる＝食い違いの向きが
    # 変わるだけになる。
    def test_unstartable_sources_ignores_schema_violation
      broken = stub_schedule_source('schema-violation', 'dest' => {'lemmy' => {'host' => 'x'}})

      assert_empty(unstartable_with(broken))
    end

    def test_unstartable_sources_reports_broken_cron
      broken = stub_schedule_source('broken-cron', 'schedule' => {'cron' => 'not a cron'})

      assert_equal(['broken-cron'], unstartable_with(broken).map(&:first))
    end

    # 止めたソースは daemon が登録しないので、起動は倒れない＝拒否の対象外。
    def test_unstartable_sources_skips_disabled
      broken = stub_schedule_source(
        'disabled-broken', 'disable' => true, 'schedule' => {'cron' => 'not a cron'}
      )

      assert_empty(unstartable_with(broken))
    end

    # 🔴 **4.10.0 リリース前レビュー 赤 A（#1589 Codex P1）: 判別キーが壊れた定義で
    # reload を止めること。**
    #
    # ⚠⚠ 以前は `Source.all` を回していたので、**定義上そこに現れない unmatched を
    # 原理的に検査できなかった**。reload は通るのに `register_all` は
    # `no source class matched` で倒れる＝次の再起動で全ソースが止まる。
    # ⚠ `feed` の typo だけではない。スキーマは `source` の中身を問わないので
    # `source: {keyword: ...}` も通る。
    def test_unstartable_sources_reports_unmatched_source
      broken = stub_schedule_source('unmatched', 'source' => {'keyword' => 'プリキュア'})

      result = unstartable_with(broken)

      assert_equal(['unmatched'], result.map(&:first))
      assert_include(result.first.last.join, 'no source class matched')
    end

    # 🔴 **赤 B: unmatched でも `disable` が逃げ道として効くこと。**拒否メッセージが
    # 「修正するか disable してください」と案内しているので、ここが効かないと嘘になる。
    def test_unstartable_sources_skips_disabled_unmatched
      broken = stub_schedule_source(
        'disabled-unmatched', 'disable' => true, 'source' => {'feeed' => 'https://example.com/x'}
      )

      assert_empty(unstartable_with(broken))
    end

    # 🔴 **赤 C: `every: '0s'` は `parse_duration` を通るが起動は倒れる。**
    def test_unstartable_sources_reports_zero_every
      broken = stub_schedule_source('zero-every', 'schedule' => {'every' => '0s'})

      assert_equal(['zero-every'], unstartable_with(broken).map(&:first))
    end

    private

    def source_path(id, suffix)
      return File.join(Environment.dir, 'config/sources', "#{id}.#{suffix}")
    end

    # `SchedulerDaemon.new` に触れたら即失敗させる。⚠ 元の Method を保存して戻す。
    # `remove_method` で戻すと本物ごと消える（singleton class に生えているため）。
    def with_daemon_guard
      original = SchedulerDaemon.method(:new)
      SchedulerDaemon.define_singleton_method(:new) do |*_args|
        raise 'reload が拒否せずに daemon へ進んでいる'
      end
      yield
    ensure
      SchedulerDaemon.define_singleton_method(:new, original)
    end

    def unstartable_with(*entries)
      @command.define_singleton_method(:config) {{'/sources' => entries}}
      return @command.send(:unstartable_sources)
    end

    # ⚠ **`Source.all` の要素ではなく、`/sources` の生の定義を返す。**判別キーは
    # 既定で妥当なものを入れておく（無いと unmatched として拾われる）。
    def stub_schedule_source(id, params)
      return {'id' => id, 'source' => {'feed' => 'https://example.com/feed'}}.merge(params)
    end

    def ack_with(source)
      said = []
      @command.define_singleton_method(:say) {|message| said.push(message)}
      @command.define_singleton_method(:find_source!) {|_id, _klass = nil| source}
      @command.ack(ACK_ID)
      return said.join("\n")
    end

    def stub_source(seconds, undelivered: false)
      source = Object.new
      source.define_singleton_method(:monitor_silence_tolerance_seconds) {seconds}
      source.define_singleton_method(:undelivered?) {undelivered}
      return source
    end
  end
end
