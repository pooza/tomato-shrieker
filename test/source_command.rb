module TomatoShrieker
  class SourceCommandTest < TestCase
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

    private

    def stub_source(seconds)
      source = Object.new
      source.define_singleton_method(:monitor_silence_tolerance_seconds) {seconds}
      return source
    end
  end
end
