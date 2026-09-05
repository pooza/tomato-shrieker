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

    private

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
