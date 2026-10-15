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

    # `before` より新しい読み込みの結果を返す。締切を過ぎたら例外。
    def wait(before)
      deadline = Time.now + @timeout
      loop do
        current = state
        return current if current['count'] > before
        raise Ginseng::GatewayError, "reload が #{@timeout} 秒以内に反映されなかった" if Time.now > deadline
        sleep(INTERVAL)
      end
    end

    def state
      response = Net::HTTP.get_response(uri)
      return JSON.parse(response.body).fetch('reload') if response.is_a?(Net::HTTPSuccess)
      raise Ginseng::GatewayError, "#{uri} returned #{response.code}"
    end

    # ⚠ `bind: 0.0.0.0`（本番）はつなぎ先ではないので、ループバックへ向ける。
    def uri
      host = Config.instance['/monitor/bind']
      host = '127.0.0.1' if ['0.0.0.0', '::', ''].include?(host.to_s)
      return URI("http://#{host}:#{Config.instance['/monitor/port']}/status.json")
    end
  end
end
