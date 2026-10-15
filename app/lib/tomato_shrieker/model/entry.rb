require 'sequel/model'

module TomatoShrieker
  class Entry < Sequel::Model(:entry)
    # 保存（insert）が通った後に上がった例外の印 (#1574)。行は残っている＝再取得されない。
    module Inserted; end

    include Package

    alias to_h values

    # 🔴 **`Entry.create` は作ったソースをそのまま渡す (#1489)。**以前はエントリごとに
    # `FeedSource.all` で全ソースを作り直し、テンプレート（`File.read` + ERB のコンパイル）も
    # エントリごとにやり直していた。⚠ ここで探すのは、ソースを渡されずに読み出した行だけ。
    def feed
      @feed ||= FeedSource.all.find {|v| v.id == values[:feed]}
      return @feed
    end

    attr_writer :feed

    def enclosures
      unless @enclosures
        uris = JSON.parse(enclosure_url)
        uris = [uris] unless uris.is_a?(Array)
        @enclosures = uris.map {|uri| Ginseng::URI.parse(uri)}.select(&:absolute?)
      end
      return @enclosures
    rescue
      return []
    end

    def tags
      unless @tags
        tags = Ginseng::Fediverse::TagContainer.new
        tags.concat(config['/feed/default_tags'])
        tags.concat(feed.tags.clone)
        tags.concat(JSON.parse(extra_tags))
        tags.concat(fetch_remote_tags) if feed.remote_tagging?
        @tags = tags.create_tags
      end
      return @tags
    rescue => e
      return [] unless feed
      logger.error(source: feed&.id, error: e)
      return feed.tags
    end

    def fetch_remote_tags
      contents = []
      ['h1', 'h2', 'h3', 'title', 'meta'].map do |v|
        contents.push(nokogiri.xpath("//#{v}").inner_text)
      end
      return feed.mulukhiya.search_hashtags(contents.join(' '))
    end

    def uri
      @uri ||= feed.create_uri(url)
      return @uri
    end

    # 🔴 **取りにいく先のホストを検証する (#1666)。**エントリの URL はフィードの書き手
    # （第三者）が決めるので、内部ホストやそこへのリダイレクトを踏ませられる。
    # ⚠ 拒否は `GatewayError` で、`tags` が握ってソースのタグだけに倒す。
    def nokogiri
      @nokogiri ||= HTTP.new.get(uri, {host_validator: Ginseng::PublicHost.validator}).body.nokogiri
      return @nokogiri
    end

    def create_template(type = :default, status = nil)
      template = feed.create_template(type)
      template[:entry] = self
      return template
    end

    def shriek(stats: nil)
      delivered = feed.shriek(
        template: create_template,
        visibility: feed.visibility,
        attachments: enclosures.map {|v| {image_url: v.to_s}}.first(4),
        stats:,
      )
      # feed.shriek は宛先ごとの例外を内部で握るので、件数を添えないと「投稿した」の
      # 意味にならない。delivered: 0 は全宛先失敗か宛先ゼロ (#1473)。
      logger.info(source: feed.id, entry: to_h, message: 'post', delivered:)
    end

    alias post shriek

    # insert は通ったが**意図して流さない**行を落とす。⚠ 行は残るが取りこぼしではない
    # （まだ touch していない / feed.time より古い / keep_years の外）。
    def self.deliverable(entry, feed)
      return nil unless feed&.touched?
      return nil if entry.published < feed.time
      return nil if feed.keep_years && entry.published < feed.keep_years.years.ago
      return entry
    end

    # 🔴 **DB が混んでいても、ここでは再試行しない (#1630)。**
    #
    # 以前は `rescue SQLite3::BusyException` で 5 回まで `retry` する形だったが、**一度も
    # 到達しない死んだコードだった**。Sequel は SQLite の例外を包み直すので、BUSY は素の
    # `Sequel::DatabaseError`（`wrapped_exception` が `SQLite3::BusyException`）で上がり、
    # 下の `rescue => e` に落ちる。ロック待ちは接続の側（Sequel 既定の 5000ms）が持つ。
    # ⚠⚠ **`retry` を「効くように」直してはいけない。**`begin` の先頭へ戻ると insert を
    # もう一度打つので、insert の後（`Entry[id]`）で混んだ run は**自分が入れた行に当たって
    # `UniqueConstraintViolation` → `nil`**＝行は残るのに失敗がどこにも計上されない。
    # 再試行を入れるなら、insert と読み出しで単位を分けること。
    def self.create(entry, feed = nil)
      inserted = false
      begin
        parser = EntryParser.new(entry)
        parser.feed = feed if feed
        id = Entry.insert(parser.parse)
        inserted = true
        record = Entry[id]
        record.feed = feed if feed
        return deliverable(record, feed)
      rescue Sequel::UniqueConstraintViolation
        # 既知のエントリ＝異常ではないので nil を返して読み飛ばす
        return nil
      rescue => e
        # 🔴🔴 **insert が通った後に落ちたら段を立てる (#1622 の Codex P2)。**
        #
        # ⚠⚠ ここまで来ると**行は残る**ので、そのエントリは次の run で
        # `Sequel::UniqueConstraintViolation` に化けて**二度と配信されない**。
        # 呼び出し元の rescue は `enter_entry_stage!` の手前なので、ここで立てないと
        # **恒久的な取りこぼしが「取得段の失敗」＝緩和が効く側**に分類される。
        # ⚠ insert より前で落ちた場合（パース失敗）は立てない。**失うものが無い。**
        feed&.enter_entry_stage! if inserted
        # ⚠ 呼び出し元（`FeedSource#fetch`）が「保存の後か」を見分けられるよう印を付ける (#1574)。
        e.extend(Inserted) if inserted
        # ⚠ 握り潰して nil を返すと、呼び出し元の FeedSource#fetch が
        # `next unless record` で読み飛ばすため record_failure に到達しない。
        # 全エントリがパース失敗しても attempted=0 の no-op success になる (#1473)。
        # fetch 側の rescue がループを継続するので、1 件の失敗でフィードは止まらない。
        logger.error(source: feed&.id, error: e, entry:)
        raise
      end
    end
  end
end
