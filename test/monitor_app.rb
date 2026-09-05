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
      SilenceAck.where(source_id: [FIXTURE_ID, SILENT_ID]).delete
      write_fixture(FIXTURE_ID, {})
      write_fixture(SILENT_ID, {'monitor' => {'silence_tolerance' => '1d'}})
      config.reload
    end

    def teardown
      SourceRunLog.where(source_id: [FIXTURE_ID, SILENT_ID, DISABLED_ID]).delete
      SilenceAck.where(source_id: [FIXTURE_ID, SILENT_ID, DISABLED_ID]).delete
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
    # ランタイムだけ「宛先がない」と咎めると食い違う。
    # ⚠ #1503 で「無効なソースは監視しない」に統一したので、run の有無に関わらず 200。
    def test_healthz_source_disabled_without_dest
      write_fixture(DISABLED_ID, {'disable' => true, 'dest' => {}})
      config.reload
      status, _headers, body = call("/healthz/source/#{DISABLED_ID}")

      assert_equal(200, status)
      assert_include(body.first, 'OK (disabled)')
    end

    # #1503: 一度稼働してから無効化したソースは run_log が残るので stale 判定まで進み、
    # しかも scheduler が register しないので executed_at が二度と前に進まない。
    # grace を跨いだ時点で恒久的に 503 になっていた。
    def test_healthz_source_disabled_after_running
      write_fixture(DISABLED_ID, {'disable' => true})
      config.reload
      record(DISABLED_ID, attempted_count: 1, delivered_count: 1, at: Time.now - 86_400)
      status, _headers, body = call("/healthz/source/#{DISABLED_ID}")

      assert_equal(200, status)
      assert_include(body.first, 'OK (disabled)')
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
      assert_include(body.first, 'silence_baseline_origin: delivery')
      assert_include(body.first, 'noop_streak: 1')
    end

    # #1505: 静かなだけと分かったら運用者が確認して緑に戻せる
    def test_healthz_source_silence_acknowledged
      record(SILENT_ID, attempted_count: 1, delivered_count: 1, at: Time.now - 172_800)
      record(SILENT_ID, attempted_count: 0, at: Time.now)

      assert_equal(503, call("/healthz/source/#{SILENT_ID}").first)

      SilenceAck.acknowledge(SILENT_ID)

      assert_equal(200, call("/healthz/source/#{SILENT_ID}").first)
    end

    # 🔴 確認は「今回は問題なかった」の記録であって「今後も問題ない」の保証ではない。
    # そこからさらに silence_tolerance が経過したら、また念押しする。
    def test_healthz_source_silence_refires_after_acknowledge
      record(SILENT_ID, attempted_count: 1, delivered_count: 1, at: Time.now - 172_800)
      record(SILENT_ID, attempted_count: 0, at: Time.now)
      # 1d のしきい値に対し、2 日前に確認した状態
      SilenceAck.acknowledge(SILENT_ID, at: Time.now - 172_800)
      status, _headers, body = call("/healthz/source/#{SILENT_ID}")

      assert_equal(503, status)
      assert_include(body.first, 'silent: true')
      assert_include(body.first, 'silence_acknowledged_at: ')
    end

    # 配信が再開したら確認記録は自然に無効化される（起点が追い越される）
    def test_healthz_source_silence_acknowledge_superseded_by_delivery
      SilenceAck.acknowledge(SILENT_ID, at: Time.now - 172_800)
      record(SILENT_ID, attempted_count: 1, delivered_count: 1, at: Time.now)
      status, = call("/healthz/source/#{SILENT_ID}")

      assert_equal(200, status)
    end

    def test_status_json_reports_silence_acknowledged_at
      record(SILENT_ID, attempted_count: 1, delivered_count: 1, at: Time.now - 172_800)

      assert_true(source_status(SILENT_ID)['silent'])
      assert_nil(source_status(SILENT_ID)['silence_acknowledged_at'])

      SilenceAck.acknowledge(SILENT_ID)

      assert_false(source_status(SILENT_ID)['silent'])
      # 「なぜ緑なのか」を答えられること
      assert_not_nil(source_status(SILENT_ID)['silence_acknowledged_at'])
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

    # #1471: ランタイムの能力欠落を検知できるようにする。
    #
    # 🔴 YJIT は Rust の無い環境ではビルド時に黙って外れ、エラーにならないまま
    # 24〜25% 遅いサーバーが出来上がる。⚠ **後者になっても誰も気づけない**ので、
    # Kuma がキーワード監視で見られる形に出す。
    def test_status_json_reports_ruby_runtime
      _status, _headers, body = call('/status.json')
      ruby = JSON.parse(body.first)['ruby']

      assert_kind_of(Hash, ruby)
      assert_equal(RUBY_VERSION, ruby['version'])
      # ⚠ Ginseng::Environment.jit? は真のとき "constant"（String）を返す。
      # JSON へ素で載せると boolean にならないので、真偽に倒れていることを見る。
      assert_boolean(ruby['yjit_available'])
      assert_boolean(ruby['yjit_enabled'])
      # 積まれていなければ有効にはなりえない
      assert_true(ruby['yjit_available']) if ruby['yjit_enabled']
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

    # 🔴 **理由の無い 503 を運用者に見せない (#1507)。**
    # #1482 で `partial` を分けてから、`error:` 行の条件が `status == "error"` の
    # ままだったので、**#1455 の形の 503 は本文に理由がゼロ**になっていた。
    # ⚠ v4.5.0 では出ていた＝後退。
    def test_healthz_source_undelivered_shows_reason
      record(FIXTURE_ID, status: SourceRunLog::STATUS_PARTIAL, attempted_count: 2,
        delivered_count: 1, error_message: 'RuntimeError: boom',
        shrieker_errors: JSON.dump('WebhookShrieker' => 1))
      _status, _headers, body = call("/healthz/source/#{FIXTURE_ID}")

      assert_include(body.first, 'RuntimeError: boom', '理由の無い 503 になっている')
      # 宛先の**種別**までは絞れる。⚠ 識別子は載せない (#1467)
      assert_include(body.first, 'shrieker_errors: {"WebhookShrieker":1}')
    end

    # 🔴🔴 **503 の本文に資格情報を出さないこと。**
    #
    # ⚠ #1507 の他のテストは `error_message` を DB へ直接書いているので、
    # **`Package.error_message` のマスクを外しても緑のまま通る**。ここだけは
    # `record_partial` を通して、マスク済みの値が保存され本文にも出ないことを見る。
    # モロヘイヤの webhook は `POST /mulukhiya/webhook/{digest}` で**パスそのものが
    # 資格情報**。
    def test_healthz_source_undelivered_masks_credentials
      digest = 'fa9c541e163ff35ac49e12dd5ad71dc4e27876a3a5514f46d074e9b6f190652d'
      stats = DeliveryStats.new
      stats.record_success(MastodonShrieker.allocate)
      stats.record_error(WebhookShrieker.allocate,
        Ginseng::GatewayError.new("Bad response 404 (https://precure.ml/mulukhiya/webhook/#{digest})"))
      SourceRunLog.record_partial(FIXTURE_ID, started_at: Time.now - 60,
        error: stats.first_error, stats:)
      _status, _headers, body = call("/healthz/source/#{FIXTURE_ID}")

      assert_not_include(body.first, digest, '503 の本文に webhook の digest が出ている')
      assert_include(body.first, '[FILTERED]')
    end

    # ⚠ 同じ行を 2 度出さない。latest が直近の配信試行そのものなら
    # `last_attempted_error:` は要らない。
    def test_healthz_source_undelivered_reason_is_not_duplicated
      record(FIXTURE_ID, status: SourceRunLog::STATUS_PARTIAL, attempted_count: 2,
        delivered_count: 1, error_message: 'RuntimeError: boom')
      _status, _headers, body = call("/healthz/source/#{FIXTURE_ID}")

      assert_not_include(body.first, 'last_attempted_error:')
      assert_equal(1, body.first.scan('RuntimeError: boom').size)
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

    # 🔴 **no-op を挟むと `latest` は success の no-op 行になる (#1507)。**
    # そのとき `status: success` ＋ `undelivered: true` だけが出て、**理由が
    # どこにも無い 503** になっていた。理由を持っているのは「直近の配信試行」の行。
    def test_healthz_source_undelivered_shows_reason_after_noop
      record(FIXTURE_ID, status: SourceRunLog::STATUS_PARTIAL, attempted_count: 2,
        delivered_count: 1, error_message: 'RuntimeError: boom',
        shrieker_errors: JSON.dump('WebhookShrieker' => 1), at: Time.now - 120)
      record(FIXTURE_ID, attempted_count: 0, at: Time.now)
      _status, _headers, body = call("/healthz/source/#{FIXTURE_ID}")

      assert_include(body.first, 'status: success', '前提: latest は no-op の success 行')
      assert_include(body.first, 'last_attempted_status: partial')
      assert_include(body.first, 'last_attempted_error: RuntimeError: boom')
      assert_include(body.first, 'last_attempted_shrieker_errors: {"WebhookShrieker":1}')
    end

    # 🔴 **未達も運用者が確認して緑に戻せること (#1506)。**
    # ⚠ 取りこぼしは再送されないので、赤を放置しても失われたものは戻らない。一方で
    # 疎なソース（本番は 57 中 17 件が 12 日間に配信試行ゼロ）は逃げ道が無いと
    # 数週間 503 に貼り付き、「いつも赤いモニター」を作ってしまう。
    def test_healthz_source_undelivered_acknowledged
      record(FIXTURE_ID, status: SourceRunLog::STATUS_PARTIAL, attempted_count: 2,
        delivered_count: 1, at: Time.now - 120)

      assert_equal(503, call("/healthz/source/#{FIXTURE_ID}").first)

      SilenceAck.acknowledge(FIXTURE_ID)

      assert_equal(200, call("/healthz/source/#{FIXTURE_ID}").first)
      assert_false(source_status(FIXTURE_ID)['undelivered'])
    end

    # 🔴 **消えるのは「確認したその試行」だけ。**確認より後の試行で再び届かなければ
    # また赤くなる。⚠ ここを「確認したら以後ずっと緑」にすると、宛先が死んだままの
    # ソースが恒久的に見えなくなる。
    def test_healthz_source_undelivered_refires_after_acknowledge
      record(FIXTURE_ID, status: SourceRunLog::STATUS_PARTIAL, attempted_count: 2,
        delivered_count: 1, at: Time.now - 120)
      SilenceAck.acknowledge(FIXTURE_ID)

      assert_equal(200, call("/healthz/source/#{FIXTURE_ID}").first)

      record(FIXTURE_ID, status: SourceRunLog::STATUS_PARTIAL, attempted_count: 2,
        delivered_count: 1, at: Time.now + 60)

      assert_equal(503, call("/healthz/source/#{FIXTURE_ID}").first)
    end

    # 🔴🔴 **確認より後に終わった run は消さない（4.8.0 リリース前レビュー・Codex P2）。**
    #
    # ⚠⚠ `executed_at` は run の**開始**時刻なので、開始時刻で ack と比べると
    # **ack の直前に始まって直後に未達で終わった run を「確認済み」として消す**。
    # 本番の最長 run は 62.6 秒（60 秒級が 5 本）あるので窓は微小ではない。
    def test_healthz_source_undelivered_survives_run_finishing_after_acknowledge
      SilenceAck.acknowledge(FIXTURE_ID, at: Time.now)
      # ack の 30 秒前に始まり、60 秒かけて未達で終わった run
      record(FIXTURE_ID, status: SourceRunLog::STATUS_PARTIAL, attempted_count: 2,
        delivered_count: 1, duration_ms: 60_000, at: Time.now - 30)

      assert_equal(503, call("/healthz/source/#{FIXTURE_ID}").first,
        '運用者が見ていない失敗を確認済みにしている')
    end

    # ⚠ no-op run は「配信試行」ではないので、確認済みの状態を崩さない。
    def test_healthz_source_undelivered_acknowledge_survives_noop
      record(FIXTURE_ID, status: SourceRunLog::STATUS_PARTIAL, attempted_count: 2,
        delivered_count: 1, at: Time.now - 120)
      SilenceAck.acknowledge(FIXTURE_ID)
      record(FIXTURE_ID, attempted_count: 0, at: Time.now + 60)

      assert_equal(200, call("/healthz/source/#{FIXTURE_ID}").first)
    end

    # 一度も配信を試みていないソースを未達扱いしない
    def test_healthz_source_undelivered_ignores_noop_only
      record(FIXTURE_ID, attempted_count: 0)
      status, = call("/healthz/source/#{FIXTURE_ID}")

      assert_equal(200, status)
    end

    # 🔴 **`/status.json` で「健全」と「判定不能」を区別できること (#1502)。**
    # #1483 で observed_since 起点にした結果、run_log 上に配信実績が無いソースは
    # 「観測開始から tolerance 経過するまで」検知されない。⚠ 検知しないこと自体は
    # 変えないが、`silent: false` で「健全」と同じ顔をするのはやめる。
    def test_status_json_silent_is_tri_state
      record(SILENT_ID, attempted_count: 0, at: Time.now - 60)
      source = source_status(SILENT_ID)

      assert_true(source.key?('silent'), 'キーごと落としてはいけない')
      assert_nil(source['silent'], '「健全」と「判定不能」を兼ねている')
      assert_equal('observation', source['silence_baseline_origin'])
    end

    # 配信実績があれば判定は確か。⚠ 起点も `delivery` になる
    def test_status_json_silent_false_when_delivered
      record(SILENT_ID, attempted_count: 1, delivered_count: 1, at: Time.now - 60)
      source = source_status(SILENT_ID)

      assert_false(source['silent'])
      assert_equal('delivery', source['silence_baseline_origin'])
    end

    # 🔴 **`/status.json` と `/healthz` が同名フィールドで違う数字を出さないこと。**
    # ⚠ 本番で再現した: `capsicum` が `/status.json` で 0/0、同じ行が DB では 1/1。
    # `last_attempted_at` は「直近の配信試行」を指しているのに、件数だけ「直近の run」
    # 由来だったので、no-op を挟むと自己矛盾していた（4.8.0 リリース前レビュー）。
    def test_status_json_attempted_counts_match_healthz
      record(FIXTURE_ID, status: SourceRunLog::STATUS_PARTIAL, attempted_count: 3,
        delivered_count: 1, at: Time.now - 120)
      record(FIXTURE_ID, attempted_count: 0, at: Time.now)
      source = source_status(FIXTURE_ID)
      _status, _headers, body = call("/healthz/source/#{FIXTURE_ID}")

      assert_equal(3, source['last_attempted_count'])
      assert_equal(1, source['last_delivered_count'])
      assert_include(body.first, 'attempted_count: 3')
      assert_include(body.first, 'delivered_count: 1')
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
