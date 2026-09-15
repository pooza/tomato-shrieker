module TomatoShrieker
  class SourceCommandTest < TestCase
    ACK_ID = '__test_source_command_ack__'.freeze

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

    private

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

    # ⚠ `Source.all` の差し替えは元の Method を保存して戻す。`remove_method` で
    # 戻すと本物ごと消える（singleton class に生えているため）。
    def unstartable_with(*sources)
      original = Source.method(:all)
      Source.define_singleton_method(:all) {sources}
      return @command.send(:unstartable_sources)
    ensure
      Source.define_singleton_method(:all, original)
    end

    def stub_schedule_source(id, params)
      source = Object.new
      source.define_singleton_method(:id) {id}
      source.define_singleton_method(:disable?) {params['disable'] == true}
      source.define_singleton_method(:to_h) {params}
      return source
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
