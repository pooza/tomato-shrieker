module TomatoShrieker
  class MonitorAppTest < TestCase
    # config/sources は環境ごとに中身が違い、CI やクリーンな作業環境では空になる。
    # 指標が空振りせず検証されるよう、テスト専用のソース定義を置いてから確かめる。
    FIXTURE_ID = '__test_monitor_app__'.freeze
    SILENT_ID = '__test_monitor_app_silent__'.freeze
    DISABLED_ID = '__test_monitor_app_disabled__'.freeze

    # teardown は異常終了で走らない。config/sources/.gitignore が `*` なので取り残しは
    # git status にも出ず、次のスケジューラ起動で偽ソースとして登録されてしまう。
    at_exit do
      Dir.glob(File.join(Environment.dir, 'config/sources', '__test_monitor_app*.yaml'))
        .each {|f| FileUtils.rm_f(f)}
    end

    def setup
      @app = MonitorApp.new
      SourceRunLog.where(source_id: [FIXTURE_ID, SILENT_ID]).delete
      write_fixture(FIXTURE_ID, {})
      write_fixture(SILENT_ID, {'monitor' => {'silence_tolerance' => '1d'}})
      config.reload
    end

    def teardown
      SourceRunLog.where(source_id: [FIXTURE_ID, SILENT_ID, DISABLED_ID]).delete
      [FIXTURE_ID, SILENT_ID, DISABLED_ID].each {|id| FileUtils.rm_f(fixture_path(id))}
      super # TestCase#teardown が config.reload する
    end

    def fixture_path(id)
      return File.join(Environment.dir, 'config/sources', "#{id}.yaml")
    end

    def write_fixture(id, extra)
      values = {
        'source' => {'feed' => "https://example.com/#{id}.rss"},
        'schedule' => {'every' => '5m'},
        'dest' => {'hooks' => ["https://example.com/#{id}/hook"]},
      }.merge(extra)
      File.write(fixture_path(id), YAML.dump(values))
    end

    def call(path)
      return @app.call({'PATH_INFO' => path})
    end

    def source_status(id)
      _status, _headers, body = call('/status.json')
      return JSON.parse(body.first)['sources'].find {|v| v['id'] == id}
    end

    def test_fixture_registered
      assert_not_nil(Source.create(FIXTURE_ID))
      assert_not_nil(source_status(FIXTURE_ID))
    end

    def test_not_found
      status, = call('/nope')

      assert_equal(404, status)
    end

    def test_healthz
      status, headers, = call('/healthz')

      assert_include([200, 503], status)
      assert_equal('text/plain; charset=utf-8', headers['content-type'])
    end

    def test_healthz_unknown_source
      status, _headers, body = call('/healthz/source/__no_such_source__')

      assert_equal(404, status)
      assert_include(body.first, '__no_such_source__')
    end

    # run が無いソースは 503 (No run recorded yet)
    def test_healthz_source_without_run
      status, _headers, body = call("/healthz/source/#{FIXTURE_ID}")

      assert_equal(503, status)
      assert_include(body.first, 'No run recorded yet')
    end

    def test_healthz_source_healthy
      record(FIXTURE_ID, attempted_count: 1, delivered_count: 1)
      status, = call("/healthz/source/#{FIXTURE_ID}")

      assert_equal(200, status)
    end

    # #1482: 部分失敗は error_streak を倒さない。
    # 99 件配信できた run と全滅した run を status の上で同じ扱いにしない。
    def test_healthz_source_partial_does_not_raise_error_streak
      record(FIXTURE_ID, status: SourceRunLog::STATUS_PARTIAL, attempted_count: 100,
        delivered_count: 99, error_message: 'RuntimeError: boom')

      assert_equal(0, SourceRunLog.error_streak(FIXTURE_ID))
    end

    # 🔴 #1504 は #1482 の「partial なら healthz は緑」を覆す。
    # ⚠ #1482 の判断（status の分類と error_streak）はそのまま。変えたのは healthz の
    # 扱いだけ。partial は「試したのに届かなかった宛先がある」ことを意味し、
    # 取りこぼしたエントリは再送されないので、緑に戻す根拠が無い。
    def test_healthz_source_partial_is_unhealthy
      record(FIXTURE_ID, status: SourceRunLog::STATUS_PARTIAL, attempted_count: 100,
        delivered_count: 99, error_message: 'RuntimeError: boom')
      status, _headers, body = call("/healthz/source/#{FIXTURE_ID}")

      assert_equal(503, status)
      assert_include(body.first, 'undelivered: true')
    end

    # #1486: スキーマは disable: true のとき dest の必須を免除しているので、
    # ランタイムだけ「宛先がない」と咎めると食い違う
    def test_healthz_source_disabled_without_dest
      write_fixture(DISABLED_ID, {'disable' => true, 'dest' => {}})
      config.reload
      status, _headers, body = call("/healthz/source/#{DISABLED_ID}")

      assert_equal(503, status)
      assert_not_include(body.first, 'No destination configured')
      assert_include(body.first, 'No run recorded yet')
    end

    # #1457: 一過性エラーのあと no-op success が来たら健全に戻る。
    # ここで 503 が残ると、新着の少ないソースが次の配信まで貼り付く。
    #
    # ⚠ #1504 以降、これが成り立つのは**配信を試みていない run**（attempted_count == 0）
    # に限る。1 件でも試みて届かなかったなら取りこぼしが確定しているので、no-op では
    # 解除しない（test_healthz_source_undelivered_survives_noop）。
    def test_healthz_source_recovers_by_noop
      record(FIXTURE_ID, status: SourceRunLog::STATUS_ERROR, attempted_count: 0, at: Time.now - 120)
      record(FIXTURE_ID, attempted_count: 0, at: Time.now)
      status, = call("/healthz/source/#{FIXTURE_ID}")

      assert_equal(200, status)
    end

    def test_healthz_source_errored
      record(FIXTURE_ID, status: SourceRunLog::STATUS_ERROR, attempted_count: 1,
        error_message: 'RuntimeError: boom')
      status, _headers, body = call("/healthz/source/#{FIXTURE_ID}")

      assert_equal(503, status)
      assert_include(body.first, 'error_streak: 1')
      # 「エラーメッセージの無い 503」を運用者に見せない
      assert_include(body.first, 'RuntimeError: boom')
    end

    # 配信できた success が来れば streak は切れて健全に戻る
    def test_healthz_source_recovers
      record(FIXTURE_ID, status: SourceRunLog::STATUS_ERROR, attempted_count: 1, at: Time.now - 120)
      record(FIXTURE_ID, attempted_count: 1, delivered_count: 1, at: Time.now)
      status, = call("/healthz/source/#{FIXTURE_ID}")

      assert_equal(200, status)
    end

    # #1473: 宛先ゼロは配信が永久に起きないが、run は no-op success を積むだけで
    # silent? も「配信実績が無ければ断定しない」ので 200 に貼り付いてしまう
    def test_healthz_source_without_destination
      write_fixture(FIXTURE_ID, {'dest' => {'tags' => ['a']}})
      config.reload
      record(FIXTURE_ID, attempted_count: 0)
      status, _headers, body = call("/healthz/source/#{FIXTURE_ID}")

      assert_equal(503, status)
      assert_include(body.first, 'No destination configured')
    end

    def test_status_json_reports_dest_count
      assert_equal(1, source_status(FIXTURE_ID)['dest_count'])

      write_fixture(FIXTURE_ID, {'dest' => {'tags' => ['a']}})
      config.reload

      assert_equal(0, source_status(FIXTURE_ID)['dest_count'])
    end

    # #1470: エラーを出さないまま配信が途絶えたソースを 503 に倒す
    def test_healthz_source_silent
      record(SILENT_ID, attempted_count: 1, delivered_count: 1, at: Time.now - 172_800)
      record(SILENT_ID, attempted_count: 0, at: Time.now)
      status, _headers, body = call("/healthz/source/#{SILENT_ID}")

      assert_equal(503, status)
      assert_include(body.first, 'silent: true')
      assert_include(body.first, 'noop_streak: 1')
    end

    # しきい値未指定のソースは、同じ状態でも沈黙では倒さない (opt-in)
    def test_healthz_source_silence_is_opt_in
      record(FIXTURE_ID, attempted_count: 1, delivered_count: 1, at: Time.now - 172_800)
      record(FIXTURE_ID, attempted_count: 0, at: Time.now)
      status, = call("/healthz/source/#{FIXTURE_ID}")

      assert_equal(200, status)
    end

    def test_status_json
      status, headers, body = call('/status.json')

      assert_equal(200, status)
      assert_equal('application/json; charset=utf-8', headers['content-type'])
      payload = JSON.parse(body.first)

      assert_boolean(payload['scheduler'])
      assert_boolean(payload['database'])
      assert_kind_of(Array, payload['sources'])
    end

    # #1433 / #1457 / #1470 で足した指標が全ソース分そろっていること
    def test_status_json_delivery_fields
      _status, _headers, body = call('/status.json')
      sources = JSON.parse(body.first)['sources']

      assert_not_empty(sources)
      sources.each do |source|
        assert_kind_of(Integer, source['error_streak'])
        assert_kind_of(Integer, source['noop_streak'])
        assert_kind_of(Hash, source['shrieker_errors'])
        assert_boolean(source['silent'])
        assert_kind_of([Hash, NilClass], source['duration_ms'])
        assert_kind_of([Float, Integer, NilClass], source['error_rate_24h'])
        assert_kind_of([String, NilClass], source['last_delivered_at'])
        assert_include([nil, 'run_log', 'fallback'], source['last_delivered_at_origin'])
        assert_kind_of([Integer, NilClass], source['silence_tolerance_seconds'])
      end
    end

    def test_status_json_reflects_delivery
      record(
        FIXTURE_ID, attempted_count: 3, delivered_count: 2,
        shrieker_errors: JSON.dump('MastodonShrieker' => 1)
      )
      source = source_status(FIXTURE_ID)

      assert_equal(3, source['last_attempted_count'])
      assert_equal(2, source['last_delivered_count'])
      assert_equal(0, source['noop_streak'])
      assert_equal('run_log', source['last_delivered_at_origin'])
      assert_equal(1, source['shrieker_errors']['MastodonShrieker'])
      assert_false(source['silent'])
    end

    # 1 ソースの不正設定で全ソース分の監視情報を巻き添えにしない
    def test_status_json_isolates_broken_source
      write_fixture(SILENT_ID, {'monitor' => {'silence_tolerance' => '0 0 * * *'}})
      config.reload
      status, _headers, body = call('/status.json')

      assert_equal(200, status)
      sources = JSON.parse(body.first)['sources']

      assert_not_nil(sources.find {|v| v['id'] == FIXTURE_ID}['error_streak'])
      # 壊れた側は握りつぶさず、そのソースだけ無効化する
      assert_nil(sources.find {|v| v['id'] == SILENT_ID}['silence_tolerance_seconds'])
    end

    def test_status_json_silence_tolerance
      record(SILENT_ID, attempted_count: 1, delivered_count: 1, at: Time.now - 172_800)
      source = source_status(SILENT_ID)

      assert_equal(86_400, source['silence_tolerance_seconds'])
      assert_true(source['silent'])
    end

    # 🔴 #1504: 2026-06 の Matrix 配信停止 (#1455) の再現。
    # hooks が 2 つあり片方だけ失敗し続ける。delivered_count > 0 なので status は
    # partial、last_delivered_at も前進し、error_streak も silent も立たない。
    # それでも「試したのに届かなかった」ので赤でなければならない。
    def test_healthz_source_undelivered
      record(FIXTURE_ID, status: SourceRunLog::STATUS_PARTIAL, attempted_count: 2,
        delivered_count: 1, error_message: 'RuntimeError: boom')
      status, _headers, body = call("/healthz/source/#{FIXTURE_ID}")

      assert_equal(503, status)
      assert_include(body.first, 'undelivered: true')
      assert_include(body.first, 'attempted_count: 2')
      assert_include(body.first, 'delivered_count: 1')
    end

    # 全宛先へ届いた run が来たら解除する
    def test_healthz_source_undelivered_recovers
      record(FIXTURE_ID, status: SourceRunLog::STATUS_PARTIAL, attempted_count: 2,
        delivered_count: 1, at: Time.now - 120)
      record(FIXTURE_ID, attempted_count: 2, delivered_count: 2, at: Time.now)
      status, = call("/healthz/source/#{FIXTURE_ID}")

      assert_equal(200, status)
    end

    # 🔴 no-op run では解除しない。新着が無いことは失敗の解消にならない。
    # ⚠ 取りこぼしたエントリは再送されないので、緑に戻す根拠が無い。
    def test_healthz_source_undelivered_survives_noop
      record(FIXTURE_ID, status: SourceRunLog::STATUS_PARTIAL, attempted_count: 2,
        delivered_count: 1, at: Time.now - 120)
      record(FIXTURE_ID, attempted_count: 0, at: Time.now)
      status, _headers, body = call("/healthz/source/#{FIXTURE_ID}")

      assert_equal(503, status)
      assert_include(body.first, 'undelivered: true')
    end

    # 一度も配信を試みていないソースを未達扱いしない
    def test_healthz_source_undelivered_ignores_noop_only
      record(FIXTURE_ID, attempted_count: 0)
      status, = call("/healthz/source/#{FIXTURE_ID}")

      assert_equal(200, status)
    end

    def test_status_json_reports_undelivered
      record(FIXTURE_ID, status: SourceRunLog::STATUS_PARTIAL, attempted_count: 3,
        delivered_count: 2)
      source = source_status(FIXTURE_ID)

      assert_true(source['undelivered'])
      assert_not_nil(source['last_attempted_at'])

      record(FIXTURE_ID, attempted_count: 3, delivered_count: 3)

      assert_false(source_status(FIXTURE_ID)['undelivered'])
    end

    # #1469: DB エラーが起きたときにだけ監視自体が壊れる、という壊れ方を防ぐ。
    # Sequel / SQLite の例外は ASCII-8BIT で上がるので、正規化前に書かれた行を
    # 読んだだけで JSON 化が落ちうる。
    #
    # ⚠ 中身が妥当な UTF-8 なら json 2.x は警告だけで通し、生成物の encoding も
    # 正規化してしまうので、レスポンスからは判別できない。json 3.0 で例外になる
    # 条件そのもの（BINARY を渡していないこと）を、/status.json が使うのと同じ
    # アクセサで確かめる。
    def test_status_json_survives_binary_error_message
      record_with_binary_error(FIXTURE_ID, 'テーブル「台詞」が無い')

      assert_equal(Encoding::UTF_8, SourceRunLog.latest_for(FIXTURE_ID).error_message.encoding)

      status, _headers, body = call('/status.json')

      assert_equal(200, status)
      source = JSON.parse(body.first)['sources'].find {|v| v['id'] == FIXTURE_ID}

      assert_include(source['last_error'], 'テーブル「台詞」が無い')
    end

    # 不正バイトは scrub で落とす。ここで落ちると本当のエラーが隠れる
    def test_status_json_survives_invalid_bytes
      record_with_binary_error(FIXTURE_ID, "boom \xff\xfe end")
      status, _headers, body = call('/status.json')

      assert_equal(200, status)
      source = JSON.parse(body.first)['sources'].find {|v| v['id'] == FIXTURE_ID}

      assert_include(source['last_error'], 'boom')
    end

    # 503 の本文にも読める形で出す。「エラーメッセージの無い 503」を運用者に見せない
    def test_healthz_source_errored_with_binary_message
      record_with_binary_error(FIXTURE_ID, 'テーブル「台詞」が無い')
      status, _headers, body = call("/healthz/source/#{FIXTURE_ID}")

      assert_equal(503, status)
      assert_include(body.first, 'テーブル「台詞」が無い')
    end

    # 保存時の正規化を迂回して、正規化前に書かれた行を再現する
    def record_with_binary_error(source_id, message)
      record(source_id, status: SourceRunLog::STATUS_ERROR, attempted_count: 1)
      SourceRunLog.latest_for(source_id).this
        .update(error_message: Sequel.blob("Sequel::DatabaseError: #{message}"))
    end

    def record(source_id, at: Time.now, **values)
      SourceRunLog.create({
        source_id:,
        executed_at: at,
        status: SourceRunLog::STATUS_SUCCESS,
        duration_ms: 100,
        attempted_count: 0,
        delivered_count: 0,
      }.merge(values))
    end
  end
end
