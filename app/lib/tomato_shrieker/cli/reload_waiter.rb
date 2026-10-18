require 'net/http'

module TomatoShrieker
  # `bin/shrieker source reload --wait` の待ち合わせ (#1529)。
  #
  # SIGHUP は非同期なので、CLI だけでは「要求した」までしか言えない。稼働中の daemon の
  # `/status.json` の `reload.count` が進むまで待ち、その回の結果を読む。
  #
  # ⚠ **監視（`/monitor/enabled`）が無効なら使えない。**読む先が無いので、HUP を送る前に断る。
  # ⚠ `count` は失敗した reload でも進む（`Scheduler#load_state`）。壊れた YAML を締切まで
  # 待たない。
  class ReloadWaiter
    INTERVAL = 1

    def initialize(timeout:)
      @timeout = timeout
    end

    def self.available?
      return Config.instance['/monitor/enabled'] == true
    end

    # HUP を送る前に呼ぶ。⚠ 送った後に読むと、その回の結果がもう入っていて待ち続ける。
    def count
      return state['count']
    end

    # `before` より新しい **reload（HUP）の**結果を返す。締切を過ぎたら例外。
    #
    # 🔴 **起動時の登録（`action: register`）の完了では返さない（#1716 の Codex P1）。**起動の途中に
    # 呼ぶと、登録の完了で `count` が進む。積まれた HUP はその後に処理されるので、そこで返すと
    # 起動の結果を「reload の結果」として出してしまう。
    def wait(before)
      deadline = Time.now + @timeout
      loop do
        current = state(deadline)
        return current if current['count'] > before && current['action'] == 'reload'
        raise Ginseng::GatewayError, "reload が #{@timeout} 秒以内に反映されなかった" if Time.now > deadline
        sleep(INTERVAL)
      end
    end

    # ⚠ **1 回の要求も締切で縛る（#1716 の Codex P2）。**`Net::HTTP` の既定の待ちは 60 秒なので、
    # 監視が詰まっていると `--timeout 1` でも 1 分待つ。
    def state(deadline = Time.now + @timeout)
      seconds = [deadline - Time.now, 1].max
      options = {open_timeout: seconds, read_timeout: seconds}
      response = Net::HTTP.start(uri.hostname, uri.port, **options) {|http| http.get(uri.request_uri)}
      unless response.is_a?(Net::HTTPSuccess)
        raise Ginseng::GatewayError, "#{uri} returned #{response.code}"
      end
      # ⚠ **`reload` が無いのは、`--wait` を知らない古い daemon（4.16.1 以前）。**pull した後・
      # 再起動する前に打つとここに来る（4.17.0 リリース前レビュー）。HUP の前に断る。
      return JSON.parse(response.body).fetch('reload') do
        raise Ginseng::GatewayError, '稼働中の daemon が --wait に対応していません（再起動の前？）'
      end
    end

    # ⚠ `bind: 0.0.0.0`（本番）はつなぎ先ではないので、ループバックへ向ける。
    # ⚠ IPv6 のアドレスは `URI` の部品として渡す（文字列に埋めると `http://::1:4567` になって
    # 読めない・#1716 の Codex P2）。`hostname` は角括弧を付けて持つ。
    def uri
      # ⚠ `::` は `::1` へ（#1716 の Codex P2）。IPv6 だけで待ち受ける環境では 127.0.0.1 に届かない。
      bind = Config.instance['/monitor/bind'].to_s
      host = {'0.0.0.0' => '127.0.0.1', '::' => '::1', '' => '127.0.0.1'}.fetch(bind, bind)
      uri = URI::HTTP.build(port: Config.instance['/monitor/port'], path: '/status.json')
      uri.hostname = host
      return uri
    end
  end
end
