module TomatoShrieker
  class SourceCommandTest < TestCase
    ACK_ID = '__test_source_command_ack__'.freeze
    ADD_ID = '__test_source_command_add__'.freeze

    # ⚠ **実 `config/sources/` には書かない (#1573)。**`add` などが見る先も差し替える。
    def setup
      @command = SourceCommand.new
      @command.define_singleton_method(:sources_dir) {Config.scratch_sources_dir}
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

      assert_not_include(said, '再び警告します')
    ensure
      SilenceAck.where(source_id: ACK_ID).delete
    end

    # #1574: エントリの取りこぼしも `ack` で確認でき、どちらに効いたかを言う。
    def test_ack_reports_lost_entries
      said = ack_with(stub_source(nil, lost: true))

      assert_include(said, 'lost_entries')
      assert_not_include(said, 'undelivered')
      assert_not_nil(SilenceAck.acknowledged_at(ACK_ID), '確認が記録されていない')
    ensure
      SilenceAck.where(source_id: ACK_ID).delete
    end

    # #1567: しきい値の無いソースでは、再警告の予定が無いことを言う。
    def test_ack_warns_when_no_tolerance
      assert_include(ack_with(stub_source(nil, undelivered: true)), '再警告はありません')
      assert_not_include(ack_with(stub_source(86_400, undelivered: true)), '再警告はありません')
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

    # #1648: `--sort` を値なしで渡すと Thor の enum 検査をすり抜け、nil を `call` して落ちていた。
    def test_status_sort_rejects_unknown_key
      error = assert_raise(Thor::Error) {SourceStatusTable.sort([], 'sort')}

      assert_include(error.message, 'error_rate')
    end

    # #1648: 組み立てに失敗した行の理由を、表の外（stderr）で言えること。
    # ⚠ 表には `build_failed` としか出ないので、空の DB に向けると原因が読めなかった。
    def test_status_row_reports_build_failure
      row = SourceStatusTable.row(broken_status_source)

      assert_equal([:build_failed], row[:problems])
      assert_equal(1, SourceStatusTable.failures([row]).size)
      assert_match(/\A__broken__: .+/, SourceStatusTable.failures([row]).first)
    end

    def test_status_failures_is_empty_for_healthy_rows
      assert_empty(SourceStatusTable.failures([{status: {id: 'ok'}, problems: [], disabled: false}]))
    end

    # 🔴 **#1648: `--problems` は、該当があれば終了コード 1・無ければ 0。**
    # ⚠ `--problems` を付けない一覧は、赤いソースがあっても 0（一覧を出しただけ）。
    def test_status_problems_exit_code
      assert_equal(1, status_exit_code([broken_status_source], problems: true))
      assert_equal(1, status_exit_code([broken_status_source], problems: true, json: true))
      assert_equal(0, status_exit_code([], problems: true))
      assert_equal(0, status_exit_code([broken_status_source], problems: false))
    end

    # #1648: 0 と負数を黙って受けて「発火はありません」と答えていた。
    def test_collisions_rejects_non_positive_hours
      [0, -5].each do |hours|
        assert_raise(Thor::Error) {SourceCommand.new([], {hours:}).collisions}
      end
    end

    # #1529: 監視が無効なら、HUP を送る前に `--wait` を断る（送った後では成否が分からない）。
    def test_reload_wait_requires_monitor
      config['/monitor/enabled'] = false
      @command.define_singleton_method(:refuse_unless_startable!) {nil}
      @command.options = {wait: true, timeout: 1}
      error = assert_raise(Thor::Error) {with_daemon_guard {@command.reload}}

      assert_include(error.message, '/monitor/enabled')
    end

    # #1745: 判定の後に終わったプロセスへの HUP は、例外ではなく「停止している」と答える。
    def test_reload_when_process_ended_after_check
      pid = spawn('true')
      Process.wait(pid)
      said = []
      @command.define_singleton_method(:say) {|message| said.push(message)}
      @command.define_singleton_method(:refuse_unless_startable!) {nil}
      @command.define_singleton_method(:reload_target) {|_daemon| [pid, :alive]}
      @command.options = {wait: false}
      @command.reload

      assert_include(said.join, '停止しています')
    end

    # #1745: PID ファイルを読めないときは、空の番号を出さない。
    def test_reload_without_readable_pid
      @command.define_singleton_method(:refuse_unless_startable!) {nil}
      @command.define_singleton_method(:reload_target) {|_daemon| [nil, :unknown]}
      @command.options = {wait: false}
      error = assert_raise(Thor::Error) {@command.reload}

      assert_include(error.message, 'PID ファイルを読めません')
    end

    # #1529: 反映できなかった定義・失敗した reload は非 0 で終わる。
    def test_report_reload
      said = []
      @command.define_singleton_method(:say) {|message| said.push(message)}
      @command.send(:report_reload, {'at' => 'T', 'result' => {'added' => ['a'], 'failed' => []}})

      assert_include(said, '  added: a')
      assert_include(said, 'reloaded at T')
      assert_raise(Thor::Error) {@command.send(:report_reload, {'error' => 'Psych::SyntaxError'})}
      error = assert_raise(Thor::Error) do
        @command.send(:report_reload, {'result' => {'failed' => ['b'], 'unmatched' => ['c']}})
      end

      assert_include(error.message, 'b, c')
    end

    # #1529: 前進するまで読み直し、前進した回の結果を返す。締切を過ぎたら例外。
    # 🔴 #1716 の Codex P1: 起動時の登録（`register`）の完了では返さない。HUP の回（`reload`）を待つ。
    def test_reload_waiter
      waiter = ReloadWaiter.new(timeout: 5)
      states = [
        {'count' => 3, 'action' => 'reload'},
        {'count' => 4, 'action' => 'register'},
        {'count' => 5, 'action' => 'reload', 'result' => {}},
      ]
      waiter.define_singleton_method(:state) {|*| states.shift}
      waiter.define_singleton_method(:sleep) {|_| nil}

      assert_equal(5, waiter.wait(3)['count'])

      stale = ReloadWaiter.new(timeout: 0)
      stale.define_singleton_method(:state) {|*| {'count' => 3, 'action' => 'reload'}}
      stale.define_singleton_method(:sleep) {|_| nil}
      assert_raise(Ginseng::GatewayError) {stale.wait(3)}
    end

    # #1716 の Codex P2: 監視が接続を受けたまま応答しなくても、1 回の要求は締切で切れる
    # （`Net::HTTP` の既定は 60 秒）。
    # ⚠ 応答しない相手は実ソケットで作るので、この 1 本だけローカルへの接続を許す（後で戻す）。
    def test_reload_waiter_request_is_bounded
      WebMock.disable_net_connect!(allow_localhost: true)
      server = TCPServer.new('127.0.0.1', 0)
      config['/monitor/bind'] = '127.0.0.1'
      config['/monitor/port'] = server.addr[1]
      started = Time.now

      assert_raise(Net::ReadTimeout) {ReloadWaiter.new(timeout: 1).state}
      assert_operator(Time.now - started, :<, 10)
    ensure
      server&.close
      WebMock.disable_net_connect!
    end

    # 🔴 `--wait` を知らない古い daemon（`reload` が無い）には、素の `KeyError` でなく
    # `GatewayError` を返す＝ `monitor_call` が Thor のエラーにする（4.17.0 リリース前レビュー）。
    def test_reload_waiter_with_old_daemon
      waiter = ReloadWaiter.new(timeout: 1)
      stub_request(:get, waiter.uri.to_s).to_return(status: 200, body: {sources: []}.to_json)

      assert_raise(Ginseng::GatewayError) {waiter.state}
    end

    # ⚠ 本番は `bind: 0.0.0.0`。つなぎ先はループバックにする。⚠ IPv6 は角括弧で包む
    # （#1716 の Codex P2）。
    def test_reload_waiter_uri
      config['/monitor/bind'] = '0.0.0.0'

      assert_equal('127.0.0.1', ReloadWaiter.new(timeout: 1).uri.host)
      ['::1', '::'].each do |bind|
        config['/monitor/bind'] = bind

        assert_equal("http://[::1]:#{config['/monitor/port']}/status.json", ReloadWaiter.new(timeout: 1).uri.to_s)
      end
    end

    # 🔴 **#1506 の眼目: 未達と沈黙の両方に効き、両方を言う。**（#1575: 以前の `ack` のテストは
    # どれも `silence_tolerance` 無しで、この経路が一度も実行されていなかった）
    def test_ack_reports_undelivered_and_silence
      said = ack_with(stub_source(259_200, undelivered: true))

      assert_include(said, 'undelivered')
      assert_include(said, 'silence_tolerance (3日)')
      assert_not_include(said, '未設定')
      assert_not_nil(SilenceAck.acknowledged_at(ACK_ID), '確認が記録されていない')
    ensure
      SilenceAck.where(source_id: ACK_ID).delete
    end

    # #1672: 身元を確かめた番号に HUP を送る。読みの間に停止が入っても生例外で落ちない。
    def test_reload_treats_missing_pid_as_stopped
      said = reload_with(pid: nil, state: :alive)

      assert(said.any? {|v| v.include?('停止しています')})
    end

    def test_reload_keeps_unknown_without_pid
      assert_raise(Thor::Error) {reload_with(pid: nil, state: :unknown)}
    end

    def test_reload_checks_state_of_read_pid
      said = reload_with(pid: 2_147_483_647, state: :alive, state_of: :dead)

      assert(said.any? {|v| v.include?('停止しています')})
    end

    private

    # `SchedulerDaemon.new` を、`pid` と状態を決め打ちした偽物に差し替えて reload を呼ぶ。
    # ⚠ `state_of` を :alive にしないこと。本物の `Process.kill` が走る。
    def reload_with(pid:, state:, state_of: :dead)
      daemon = Object.new
      daemon.define_singleton_method(:pid) {pid}
      daemon.define_singleton_method(:alive_state) {state}
      daemon.define_singleton_method(:alive_state_of) {|_pid| state_of}
      said = []
      @command.define_singleton_method(:refuse_unless_startable!) {nil}
      @command.define_singleton_method(:say) {|message = ''| said.push(message.to_s)}
      original = SchedulerDaemon.method(:new)
      SchedulerDaemon.define_singleton_method(:new) {|*_args| daemon}
      @command.reload
      return said
    ensure
      SchedulerDaemon.define_singleton_method(:new, original)
    end

    # `source status` を回し、終了コードを返す。出力は捨てる。
    # ⚠ CLI では `Thor::Error` が終了コード 1 になる（`MainCommand.exit_on_failure?`）。
    def status_exit_code(sources, **options)
      command = SourceCommand.new([], options)
      command.define_singleton_method(:status_sources) {|_id| sources}
      [:puts, :print_table, :say_error].each {|name| command.define_singleton_method(name) {|*| nil}}
      command.status
      return 0
    rescue Thor::Error
      return 1
    end

    # `SourceStatus.build` が落ちるソース（必要なメソッドを持たない）。
    def broken_status_source
      source = Object.new
      source.define_singleton_method(:id) {'__broken__'}
      source.define_singleton_method(:disable?) {false}
      source.define_singleton_method(:monitored?) {true}
      return source
    end

    def source_path(id, suffix)
      return File.join(Config.scratch_sources_dir, "#{id}.#{suffix}")
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

    def stub_source(seconds, undelivered: false, lost: false)
      source = Object.new
      source.define_singleton_method(:monitor_silence_tolerance_seconds) {seconds}
      source.define_singleton_method(:undelivered?) {undelivered}
      source.define_singleton_method(:lost_entries?) {lost}
      return source
    end
  end
end
