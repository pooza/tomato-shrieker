module TomatoShrieker
  class MonitorAppTest < TestCase
    # config/sources は環境ごとに中身が違い、CI やクリーンな作業環境では空になる。
    # 指標が空振りせず検証されるよう、テスト専用のソース定義を置いてから確かめる。
    FIXTURE_ID = '__test_monitor_app__'.freeze
    SILENT_ID = '__test_monitor_app_silent__'.freeze

    def setup
      @app = MonitorApp.new
      SourceRunLog.where(source_id: [FIXTURE_ID, SILENT_ID]).delete
      write_fixture(FIXTURE_ID, {})
      write_fixture(SILENT_ID, {'monitor' => {'silence_tolerance' => '1d'}})
      config.reload
    end

    def teardown
      SourceRunLog.where(source_id: [FIXTURE_ID, SILENT_ID]).delete
      [FIXTURE_ID, SILENT_ID].each {|id| FileUtils.rm_f(fixture_path(id))}
      super # TestCase#teardown が config.reload する
    end

    def fixture_path(id)
      return File.join(Environment.dir, 'config/sources', "#{id}.yaml")
    end

    def write_fixture(id, extra)
      values = {
        'source' => {'feed' => "https://example.com/#{id}.rss"},
        'schedule' => {'every' => '5m'},
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

    # #1457: 直近が no-op success でも、その手前の連続エラーを見逃さない
    def test_healthz_source_error_streak_survives_noop
      record(FIXTURE_ID, status: SourceRunLog::STATUS_ERROR, attempted_count: 1, at: Time.now - 120)
      record(FIXTURE_ID, attempted_count: 0, at: Time.now)
      status, _headers, body = call("/healthz/source/#{FIXTURE_ID}")

      assert_equal(503, status)
      assert_include(body.first, 'error_streak: 1')
    end

    # 配信できた success が来れば streak は切れて健全に戻る
    def test_healthz_source_recovers
      record(FIXTURE_ID, status: SourceRunLog::STATUS_ERROR, attempted_count: 1, at: Time.now - 120)
      record(FIXTURE_ID, attempted_count: 1, delivered_count: 1, at: Time.now)
      status, = call("/healthz/source/#{FIXTURE_ID}")

      assert_equal(200, status)
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

    def test_status_json_silence_tolerance
      record(SILENT_ID, attempted_count: 1, delivered_count: 1, at: Time.now - 172_800)
      source = source_status(SILENT_ID)

      assert_equal(86_400, source['silence_tolerance_seconds'])
      assert_true(source['silent'])
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
