module TomatoShrieker
  class IcalendarSourceTest < TestCase
    def test_all
      assert_kind_of(Enumerator, IcalendarSource.all)
    end

    def test_ical
      IcalendarSource.all.each do |source|
        assert_kind_of(Icalendar::Calendar, source.ical)
      end
    end

    # 🔴🔴 **#1615 の Codex P1: ical の取得が落ちた run は取得段。**
    #
    # ⚠⚠ `entries` は `enum_for` ＝ **Enumerator なので、代入しただけでは ical を
    # 取りに行かない**。しかも Enumerator は `empty?` を持たないので `present?` が
    # **中身を見ずに true** を返す。`to_a` で先に評価しないと、**取得の失敗が
    # `entry_stage: true` で保存され**、しきい値を緩めているソースが
    # **一過性の取得失敗 1 回で 503** になる。
    def test_entry_stage_not_marked_when_ical_fetch_fails
      source = build_entry_stage_source
      stats = attach_stats(source)
      stub_request(:get, %r{//ical\.example\.test/}).to_return(status: 500)

      assert_raise(Ginseng::GatewayError) {source.exec}
      assert_false(stats.entry_stage?)
    end

    # ⚠ 予定を読んだ後に落ちたら段が立つ（そのぶんは時刻で 1 度しか流れず取り返せない）。
    def test_entry_stage_marked_after_reading_entries
      source = build_entry_stage_source
      stats = attach_stats(source)
      def source.create_template(*)
        raise 'template broken'
      end

      assert_raise(RuntimeError) {source.exec}
      assert_true(stats.entry_stage?)
    end

    def build_entry_stage_source
      return IcalendarSource.new(
        'id' => '__test_icalendar_entry_stage__',
        'source' => {'calendar' => 'https://ical.example.test/test.ics'},
        'schedule' => {'cron' => '0 0 * * *'},
        'dest' => {'hooks' => ['https://hook.example.test/ical']},
      )
    end

    def test_keyword
      IcalendarSource.all.select(&:keyword).each do |source|
        assert_kind_of(Regexp, source.keyword)
      end
    end

    def test_negative_keyword
      IcalendarSource.all.select(&:negative_keyword).each do |source|
        assert_kind_of(Regexp, source.negative_keyword)
      end
    end

    def test_sanitize_mode
      IcalendarSource.all.each do |source|
        assert_includes([:fedi, :html], source.sanitize_mode)
      end
    end

    def test_fedi_sanitize?
      IcalendarSource.all.each do |source|
        assert_kind_of([TrueClass, FalseClass], source.fedi_sanitize?)
      end
    end

    def test_google?
      IcalendarSource.all.each do |source|
        assert_kind_of([TrueClass, FalseClass], source.google?)
      end
    end

    def test_sanitize
      source = %{<a href="https://shonenjumpplus.com/episode/17106371859967525169">https://shonenjumpplus.com/episode/17106371859967525169</a><br>感想には是非、以下のタグをどうぞ！<br>#勇者アバン_42話<br>#勇者アバン_11巻 (11巻2話目にあたります)<br><br>#delmulin #更新}
      sanitized = %{https://shonenjumpplus.com/episode/17106371859967525169\n感想には是非、以下のタグをどうぞ！\n#勇者アバン_42話\n#勇者アバン_11巻 (11巻2話目にあたります)\n\n#delmulin #更新}

      assert_equal(sanitized, source.sanitize)
    end

    def test_fix_google_calendar_entry
      source = IcalendarSource.new({})
      entry = source.fix_google_calendar_entry(
        body: "無理はせず、スコアのある、蓄積開始後ほこらに備えましょう #頑張りましたで称号\n\n#DQW期限\n\nGoogle Meet に参加: https://meet.google.com/aaa-bbbc-ccc\n\nMeet の詳細: https://support.google.com/a/users/ans",
        location: '渋谷WOMBLOUNGE, 日本、〒150-0044 東京都渋谷区円山町２−１６',
      )

      assert_equal("無理はせず、スコアのある、蓄積開始後ほこらに備えましょう #頑張りましたで称号\n\n#DQW期限", entry[:body])
      assert_equal('渋谷WOMBLOUNGE', entry[:location])
    end

    def test_entries
      IcalendarSource.all do |source|
        assert_kind_of(Enumerator, source.entries)
        source.entries.first(5).each do |entry|
          assert_kind_of(Hash, entry)
          assert_kind_of(Time, entry[:start_date])
          assert_kind_of(Time, entry[:end_date])
          assert_kind_of([String, NilClass], entry[:title])
          assert_kind_of([String, NilClass], entry[:body])
          assert_kind_of([String, NilClass], entry[:description])
        end
      end
    end

    # 🔴 **#1616: `present?` で取得しに行かないこと。**
    #
    # ⚠ 以前は `entries.present?` を上書きしていたが、`entries` は Enumerator なので
    # **中身を見ずに常に true** で、呼び出し元も無かった。直すと `source.present?` という
    # ありふれた書き方がネットワーク取得になるので、上書きごと消した（Object#present? に戻る）。
    def test_present_does_not_fetch
      source = build_entry_stage_source
      source.define_singleton_method(:entries) {raise 'present? が ical を取りに行った'}

      assert_predicate(source, :present?)
    end

    # ⚠ コマンド由来のソースは URL を持たない (#1691)。
    def test_uri
      IcalendarSource.all do |source|
        assert_kind_of(source.command? ? NilClass : Ginseng::URI, source.uri)
      end
    end

    # 🔴 **#1691: CI でも 1 本は回ること。**`test/sources/ical-command.yaml` が無いと
    # 上のループは 1 度も回らない。⚠ 今日の日付の予定を 1 件出すので、いつ走らせても
    # エントリが 1 件は出る。
    def test_command_fixture
      source = IcalendarSource.all.find {|v| v.id == 'ical-command'}

      assert_predicate(source, :command?)
      assert_false(source.google?)
      assert_equal(2, source.ical.events.count)
      entry = source.entries.first

      assert_equal('コマンド由来の予定（今日）', entry[:title])
      assert_true(entry[:is_today])
      assert_equal('#fixture #command', entry[:body])
      assert_true(entry[:all_day])
    end

    # #1691: コマンドの出力を、URL から取ったものと同じ規則で予定にする。
    def test_command_entries
      source = build_command_source
      date = Date.today + 2
      stub_output(source, command_ics(date))
      entry = source.entries.to_a.first

      assert_equal(1, source.entries.count)
      assert_equal(date, entry[:start_date].to_date)
      assert_equal(date, entry[:end_date].to_date, '終了日を書かない終日の予定は、開始日と同じ日')
      assert_equal(2, entry[:countdown])
      assert_false(entry[:is_today])
      assert_true(entry[:all_day])
      assert_equal('「ドラゴンクエストV 天空の花嫁」の発売日から34周年', entry[:title])
    end

    # #1693: `RRULE` つきの終日予定に `DTEND` が無くても落ちない（規格上は 1 日の予定）。
    def test_rrule_all_day_without_dtend
      source = build_command_source
      date = Date.today - 10
      stub_output(source, [
        'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//fixture//JA',
        'BEGIN:VEVENT', 'DTSTAMP:20260101T000000Z', 'UID:rrule-0@fixture',
        "DTSTART;VALUE=DATE:#{date.strftime('%Y%m%d')}",
        'RRULE:FREQ=DAILY', 'SUMMARY:毎日の予定',
        'END:VEVENT', 'END:VCALENDAR'
      ].join("\n"))
      entry = source.entries.to_a.first

      assert_equal(1, source.entries.count)
      assert_equal(Date.today, entry[:start_date].to_date)
      assert_equal(Date.today, entry[:end_date].to_date)
      assert_true(entry[:is_today])
      assert_true(entry[:all_day])
    end

    # #1707: 命日など、予定の告知でない記念日は見出し（「❗️本日❗️」）を付けない。
    def test_anniversary_template
      params = command_params
      params['dest']['template'] = 'anniversary'
      source = IcalendarSource.new(params)
      date = Date.today
      stub_output(source, command_ics(date))
      template = source.create_template
      template[:entry] = source.entries.to_a.first

      assert_equal(
        "#{date.month}月#{date.day}日は、「ドラゴンクエストV 天空の花嫁」の発売日から34周年。\n#dq5\n",
        template.to_s,
      )
    end

    # ⚠ `days`（何日前から出すか）の外の予定は出さない。コマンドは今年と来年のぶんを全部返す。
    def test_command_entries_outside_days
      source = build_command_source
      stub_output(source, command_ics(Date.today + 4))

      assert_empty(source.entries.to_a)
    end

    # ⚠ **空の出力は「該当なし」で正常**（予定 0 件の VCALENDAR と同じ）。段も立てない。
    def test_command_empty_output
      ['', "\n", "BEGIN:VCALENDAR\nVERSION:2.0\nEND:VCALENDAR\n"].each do |output|
        source = build_command_source
        stub_output(source, output)
        stats = attach_stats(source)
        source.exec

        assert_empty(source.entries.to_a)
        assert_false(stats.entry_stage?)
      end
    end

    # 🔴 **空でないのに iCalendar として読めない出力は、取得段の失敗にする。**⚠⚠ パーサは
    # 入力によっては例外を出さず何も返さない（下の 2 つ目）ので、黙って通すと壊れたコマンドが
    # 「予定なし」の success を積み続ける。
    def test_command_invalid_output
      ["今日は記念日ではありません\n", "garbage\nline\n"].each do |output|
        source = build_command_source
        stub_output(source, output)
        stats = attach_stats(source)
        error = assert_raise(RuntimeError) {source.exec}

        assert_include(error.message, 'invalid iCalendar output')
        assert_false(stats.entry_stage?)
      end
    end

    # ⚠ コマンドが非 0 で終わった run も取得段。理由（stderr）を例外メッセージに載せる。
    def test_command_failure
      source = build_command_source('echo "calendar name required" >&2; exit 1')
      stats = attach_stats(source)
      error = assert_raise(RuntimeError) {source.exec}

      assert_include(error.message, 'calendar name required')
      assert_false(stats.entry_stage?)
    end

    # 🔴 #1703: 締切は `/source/ical/timeout`（`/source/timeout` ではない）。締切で落ちた run は取得段の失敗。
    def test_command_timeout
      params = command_params('sleep 30')
      params['source']['ical']['timeout'] = 1
      params['source']['timeout'] = 600
      source = IcalendarSource.new(params)
      stats = attach_stats(source)

      assert_equal(1, source.command_timeout)
      assert_raise(Timeout::Error) {source.exec}
      assert_false(stats.entry_stage?)
    end

    # ⚠ 読めない出力を例外メッセージへ載せるときも、資格情報は伏せる（run_log・Sentry へ流れる）。
    def test_command_invalid_output_is_masked
      source = build_command_source("echo error at #{SECRET_ENV}")
      error = assert_raise(RuntimeError) {source.ical}

      assert_include(error.message, 'invalid iCalendar output')
      assert_not_include(error.message, SECRET_ENV)
    end

    # 🔴 **#1692 の Codex P2: 空の `command` は URL の側へ流さず、取得段の失敗にする。**
    # ⚠ `present?` で見ていたときは `@http.get(nil)` へ進んでいた。`sh -c ''` を走らせると
    # 「出力なし」の success になるので、走らせる前に落とす。
    def test_command_blank
      ['', '  ', [], ['']].each do |command|
        params = command_params
        params['source']['ical']['command'] = command
        source = IcalendarSource.new(params)
        stats = attach_stats(source)
        error = assert_raise(RuntimeError) {source.exec}

        assert_predicate(source, :command?)
        assert_equal('/source/ical/command is blank', error.message)
        assert_false(stats.entry_stage?)
      end
    end

    # 🔴 **4.16.0 リリース前レビュー: パーサが上げる例外は、型に関わらず伏せ字を通す。**
    #
    # ⚠⚠ 日付として読めない値は `Icalendar::Values::Date::FormatError`（`ArgumentError` の子）で
    # 上がり、メッセージに値がそのまま入る（`Failed to parse "<値>"`）。`ParseError` だけを
    # 受けていたときは、これが run_log・`/status.json`・Sentry へ素通しだった。
    def test_command_parser_error_is_masked
      lines = [
        'BEGIN:VCALENDAR', 'VERSION:2.0', 'BEGIN:VEVENT', 'UID:a', 'DTSTART;VALUE=DATE:%s',
        'SUMMARY:x', 'END:VEVENT', 'END:VCALENDAR', ''
      ]
      script = %(printf "#{lines.join('\n')}" "$PUSH_URL")
      source = build_command_source(script)
      stats = attach_stats(source)
      error = assert_raise(RuntimeError) {source.exec}

      assert_include(error.message, 'invalid iCalendar output')
      assert_not_include(error.message, 'AbCdEf123456')
      assert_false(stats.entry_stage?)
    end

    # 🔴 **4.16.0 リリース前レビュー: 出力に不正なバイト列があっても、本来の理由で落ちる。**
    # ⚠ 以前は `blank?` が `ArgumentError: invalid byte sequence in UTF-8` を上げていた。
    def test_command_output_with_invalid_bytes
      error = assert_raise(RuntimeError) {build_command_source("printf '\\377\\376 invalid'").ical}

      assert_include(error.message, 'invalid iCalendar output')
      assert_predicate(error.message, :valid_encoding?)
    end

    # 🔴 **4.16.0 リリース前レビュー: 日次の実行とリマインドは、同じコマンドを同時に走らせない。**
    #
    # ⚠⚠ 別々のジョブ（別スレッド）が同じ `Ginseng::CommandLine` を `exec` すると、片方が
    # 結果を読む前にもう片方が `@stdout` / `@status` を nil に戻す。
    def test_command_runs_one_at_a_time
      source = build_command_source
      running = 0
      overlapped = false
      command = Ginseng::CommandLine.new(['true'])
      command.define_singleton_method(:exec) do |**|
        running += 1
        overlapped = true if running > 1
        sleep(0.05)
        running -= 1
        @stdout = ''
        @stderr = ''
        @status = 0
      end
      source.define_singleton_method(:command) {command}
      Array.new(4) {Thread.new {source.run_command}}.each(&:join)

      assert_false(overlapped)
    end

    # 🔴 **`dir` / `env` は `/source/ical` の下から読む。**⚠ `/source/dir` / `/source/env` は
    # CommandSource のもの。
    def test_command_is_built_from_ical
      command = build_command_source.command

      assert_equal(['cat', 'test/fixtures/command.ics'], command.args)
      assert_equal(File.join(Environment.dir, 'test'), command.dir)
      assert_equal(SECRET_ENV, command.env['PUSH_URL'])
      assert_equal(File.join(Environment.dir, 'test/Gemfile'), command.env['BUNDLE_GEMFILE'])
      assert_include(command.secrets, SECRET_ENV)
      assert_include(command.secrets, 'https://hook.example.test/ical-command')
    end

    # 🔴 **1 つの定義から立つソースは 1 つ。**⚠ 判別キーを `/source/command` にすると、
    # `CommandSource` も一緒に立つ。
    def test_command_definition_matches_one_class
      sources = Source.all([command_params]).to_a

      assert_equal([IcalendarSource], sources.map(&:class))
      assert_empty(Source.unmatched_ids([command_params]))
    end

    # ⚠ URL のソースは今までどおり（コマンドとして扱わない）。
    def test_url_source_is_not_command
      source = build_entry_stage_source

      assert_false(source.command?)
      assert_empty(source.command_params)
      assert_kind_of(Ginseng::URI, source.uri)
    end

    def test_google_with_command
      assert_false(build_command_source.google?)
      params = command_params
      params['source']['google'] = true

      assert_true(IcalendarSource.new(params).google?)
    end

    SECRET_ENV = 'https://kuma.example.test/api/push/AbCdEf123456'.freeze

    def build_command_source(script = nil)
      return IcalendarSource.new(command_params(script))
    end

    def command_params(script = nil)
      return {
        'id' => '__test_icalendar_command__',
        'source' => {
          'ical' => {
            'command' => script || ['cat', 'test/fixtures/command.ics'],
            'dir' => File.join(Environment.dir, 'test'),
            'env' => {'PUSH_URL' => SECRET_ENV},
          },
        },
        'dest' => {'hooks' => ['https://hook.example.test/ical-command'], 'sanitize' => 'html'},
      }
    end

    def stub_output(source, output)
      source.define_singleton_method(:run_command) {output}
    end

    def command_ics(date)
      return [
        'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//dqdai-anniv//numbering_title//JA',
        'BEGIN:VEVENT', 'DTSTAMP:20260101T000000Z', 'UID:numbering_title-0@dqdai-anniv',
        "DTSTART;VALUE=DATE:#{date.strftime('%Y%m%d')}",
        'DESCRIPTION:#dq5',
        'SUMMARY:「ドラゴンクエストV 天空の花嫁」の発売日から3', ' 4周年',
        'END:VEVENT', 'END:VCALENDAR'
      ].join("\n")
    end

    def test_prefix
      IcalendarSource.all do |source|
        assert_kind_of([String, NilClass], source.prefix)
      end
    end
  end
end
