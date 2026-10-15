# ソース定義 YAML リファレンス

⚠ **`config/sources/*.yaml` の正本。**⚠⚠ **実体は gitignore されていて oscura にしか無い。**

🔴 **キーの正本は [`config/schema/source.yaml`](../config/schema/source.yaml)。**このファイルは読み方の説明で、食い違ったらスキーマが正しい（`bin/shrieker source validate` が見るのもスキーマ）。⚠ `config/schema/base.yaml`（`rake config:lint` が見る）は**ソース定義を見ない**。`source.yaml` を参照も複製もしておらず、`sources` は「オブジェクトの配列」としか書いていない（json-schema gem が YAML ファイルへの `$ref` を解決できないため）。ソースのキーを足すなら `source.yaml` へ。⚠ ＝ `config/local.yaml` の `sources:` に書いた定義は、`rake config:lint` でも `source validate`（`config/sources/` のファイルだけを見る）でも検査されない。

各ソースは `config/sources/<id>.yaml` に **1 ファイル 1 ソース**で定義する。**ファイル名が id になる**ので、ファイルの中に `id` は書かない。起動時と `source reload` のときにディレクトリ内の `*.yaml` / `*.yml` を読み込む。

基本構造:

```yaml
# config/sources/blog.yaml（id は blog）
source:
  # ソース固有の設定（種別はここのキーで決まる）
schedule:
  every: 1h             # every / cron / at のいずれか。省略時は種別ごとの既定
dest:
  # 投稿先固有の設定（有効なソースは 1 つ以上必須）
  tags:                 # ハッシュタグ（先頭の # を除いた文字列の配列）
    - tag1
  template: default     # ERB テンプレート名（views/ 配下）
```

⚠ トップレベルに書けるのは `source` / `dest` / `schedule` / `monitor` / `keep` / `enclosure` / `disable` / `test` だけ（`additionalProperties: false`）。旧形式の `sources:` 配列は `config/local.yaml` でだけ読める（そこでは `id` を書く）。

### Source 設定項目

| Source | 主要キー | 備考 |
|--------|----------|------|
| TextSource | `/source/text` | 定型文 |
| CommandSource | `/source/command` | 文字列（sh経由）または配列（shellescape）。`/source/dir`, `/source/env`, `/source/delimiter`（デフォルト `=====`） |
| FeedSource | `/source/feed`（`/source/url` でも可） | `/keep/years`（エントリを覚えておく年数・既定 3）、`/dest/prefix`、`/dest/account/bot`、`/enclosure/enable` / `/enclosure/negative_keyword` |
| GoogleNewsSource | `/source/news/phrase` | FeedSource の設定項目も利用可。`/source/news/dedupe`（デフォルト true）。`/google/news/cleaner/url` を application.yaml に設定すると [google-news-rss-cleaner](https://github.com/pooza/google-news-rss-cleaner) 経由で実記事 URL に解決し、Google News が古記事に付ける fresh pubDate 問題も併せて回避する |
| IcalendarSource | `/source/ical`（`/source/calendar` でも可） | iCalendar (.ics) の URL、またはコマンド（`/source/ical/command`・下記）。`/source/days`（何日前から出すか・既定 3）、`/source/keyword` / `/source/negative_keyword`、`/source/google` |
| YouTubeChannelSource | `/source/youtube/channel/id`（`/source/youtube/channel/url` でも可） | FeedSource の設定項目も利用可（`/source/keyword` など） |
| GitHubRepositorySource | `/source/github/repository`（`/source/github/repos` でも可） | `owner/name` の形。`/source/github/timeline`（`releases` / `commits`） |

🔴 **CommandSource に資格情報を渡すなら `/source/env` に書く (#1623)。**`/source/env` の値は、キー名を見ずに全部がログ（`"command":` / `"env":`）と失敗時の例外メッセージから伏せられる。宛先の資格情報（`/dest/hooks` の URL・`/dest/mastodon/token` など）も同じく伏せる。⚠ **`/source/command` の中に直接書いた資格情報は、上のどれとも一致しなければ伏せられない**（webhook URL や Uptime Kuma の push URL はトークンがパスに入るので、上流のキー名・URL のマスクでも拾えない）。⚠ 8 文字未満の値は伏せない（`DEBUG: '1'` まで伏せると、ログの同じ文字が全部 `[FILTERED]` になって読めなくなる）。⚠⚠ **伏せるのは「書いたとおりの形」（とシェルエスケープした形）だけ。**コマンドが加工して書き出した形（URL のパスだけ・クエリを落とした URL・JSON や HTML のエスケープ・URL エンコード・Base64・途中で折り返された値）は伏せられない。

### コマンドの出力を iCalendar として読む（IcalendarSource・#1691）

`/source/ical` に URL ではなくコマンドを書くと、その標準出力を iCalendar として読む。事前告知（`/source/days` 日前から当日まで毎日）・テンプレート（`views/calendar.erb`）・リマインド・監視は URL のときと同じ。

予定の告知でない記念日（命日など）は `dest.template: anniversary` で `views/anniversary.erb` を使う。「❗️本日❗️」などの見出しを付けず「4月9日は、〈題名〉。」＋説明の形で出す（#1707）。

```yaml
source:
  ical:
    command:            # 配列（argv）または文字列（sh -c）。CommandSource の /source/command と同じ
      - bin/anniv.rb
      - --ics
      - numbering_title
    dir: /home/deploy/repos/dqdai-anniv
    # env:              # 資格情報はここへ（値はログと例外メッセージから伏せる）
  days: 3
dest:
  sanitize: html        # ⚠ 既定（fedi）は本文の `#タグ` を `# タグ` に崩す
  hooks:
    - https://...
```

- 🔴 **`dir` / `env` は `/source/ical` の下に書く。**`/source/dir` / `/source/env` は CommandSource のもので、こちらでは読まない。⚠ `/source/command` を一緒に書くと CommandSource も立つ（1 つの定義から 2 つのソース）
- コマンドの組み立て（bundler・`BUNDLE_GEMFILE`・伏せ字・`bundle …` で始まるときの `bundle install`）は CommandSource と共有している（`CommandRunner`）。上の資格情報の注意もそのまま当てはまる。⚠ `bundle install` が走るのは `command` を**配列**で書いたときだけ（文字列は `sh -c` に包まれる。CommandSource も同じ）
- 🔴 **空を正常として扱うので、「何も返さなくなった」コマンドは緑のまま。**取得先が空の一覧を返す・例外を握って 0 で終わる、といった壊れ方は error にならない。拾えるのは `/monitor/silence_tolerance`（無配信の許容期間）だけなので、**予定の間隔より少し長い値を必ず付ける**
- ⚠ **`schedule.remind.enable: true` にすると、コマンドが `remind.minutes` 分ごとにも走る**（5 分なら 1 日 288 回）。`bin/shrieker source fetch` でも走る。副作用のあるコマンド・重いコマンドを書かない
- ⚠ **実行する時刻は `schedule.cron` で書く。**IcalendarSource は既定の cron（`0 0 * * *`）を持ち、`schedule.every` より優先する（URL のときも同じ）
- ⚠ コマンドに締切は無い。戻らないコマンドは、そのソースの以後の実行を塞ぐ（CommandSource も同じ）
- **空の出力は「該当なし」で正常**（予定 0 件の `VCALENDAR` と同じ）。🔴 **空でないのに iCalendar として読めない出力は error**（取得段の失敗）。コマンドが非 0 で終わったときも同じ
- ⚠ **本文のハッシュタグを生かすなら `dest.sanitize: html` を付ける。**既定の `fedi` は、投稿先に再解釈させないために `#` / `@` の後ろへ空白を入れる。本番の予定のソース（`delmulin-numbering-title` など）はどれも `html`
- ⚠ コマンドは「今日のぶん」ではなく**先の予定まで**返すこと（`days` 日前から拾うため）。年をまたぐので、来年のぶんも要る
- ⚠ 終日の予定に `DTEND` を書くなら注意。iCalendar の規格では終了日は「翌日」だが、1 日戻すのは Google カレンダーのとき（`/source/google`）だけ。書かなければ開始日と同じ日になる

### URL の検証（`source validate`・#1461）

スキーマの `format: uri`（`/source/feed`・`/source/url`・`/source/calendar`・`/source/ical`・`/source/news/url`・`/dest/hooks` など）は、**絶対 URI（スキーム必須）**を要求する。`example.com/feed` や空文字は NG。

- ⚠ **この判定は ginseng-core の側にある**（1.18.0）。こちらのスキーマに書いてあるのは `format: uri` だけなので、効いていることは `SourceValidatorTest#test_invalid_uri_is_ng` で受けている
- ⚠ **`host:port/path`（スキームの書き忘れ）は通る。**`localhost:3000/clean` は規格上 `localhost` というスキームの絶対 URI として読める。スキームは絞っていない（`webcal:` などを弾くため）
- `source.news` は `phrase`（空文字・空白だけは NG）か `url` のどちらかが要る。どちらも無い定義は「どのクラスにもマッチしない」で NG になる

### キーワードフィルタ（FeedSource 系共通）

- `/source/keyword` — 含むエントリのみ対象（正規表現可）
- `/source/negative_keyword` — 含まないエントリのみ対象（正規表現可）

### 実装に無いキー（FeedSource）

⚠ 以前ここにあった `/dest/multi_entries` / `/dest/limit` / `/source/title/unique` は実装に無い（書くと `source validate` が NG にする）。

⚠ **`/dest/category` は書けるが、絞り込みには使われていない。**読むのは `FeedSource#category` だけで、`bin/shrieker source fetch` のサマリーに値がそのまま出る。エントリを絞るなら `/source/keyword` / `/source/negative_keyword` を使う。

### Shrieker 設定項目

| Shrieker | 主要キー | 備考 |
|----------|----------|------|
| MastodonShrieker | `/dest/mastodon/url`, `/dest/mastodon/token` | 権限: `write:statuses`（画像は `write:media`）。`/dest/visibility` |
| MisskeyShrieker | `/dest/misskey/url`, `/dest/misskey/token` | 権限: `write:notes`（画像は `write:drive`） |
| WebhookShrieker | `/dest/hooks` | Slack Incoming Webhooks 互換の宛先の配列（Discord は末尾に `/slack`）。URL 文字列のほかオブジェクト形式も可 → [Webhook 宛先の指定形式](#webhook-宛先の指定形式) |
| LineShrieker | `/dest/line/user_id`, `/dest/line/token` | チャンネルアクセストークン（長期） |
| PieFedShrieker | `/dest/piefed/host`, `/dest/piefed/user_id`, `/dest/piefed/password`, `/dest/piefed/community_id` | `host` は**ホスト名だけ**（接続先は常に `https://<host>`。スキーム・ポート・パスを書くと `source validate` が NG にする）。`community_id` は整数。`/dest/piefed/template`。API の版は `config/local.yaml` の `/piefed/api/version`（デフォルト alpha）。宛先ごとに変えるなら `/dest/piefed/api_version` |
| NostrShrieker | `/dest/nostr/private_key` | nsec 形式対応。リレーは `/nostr/relays`（application.yaml） |

🔴 **宛先はリダイレクトを追わない（4.14.0・ginseng-core 2.0.0）。宛先の URL は `https://` の最終オリジンで書く。**宛先が 3xx を返すと、その配信は `Ginseng::GatewayError: Bad response 301`（など）で失敗する。これまでは 301 / 302 を追って GET に化け、本文が落ちたまま「成功」と数えていた。⚠ `bin/shrieker source validate` は `/dest/hooks`・`/dest/mastodon/url`・`/dest/misskey/url` が `http://` のとき WARN を出す（`disable: true` の定義には出さない）。読み方は [monitoring.md](monitoring.md#bad-response-3xx-の読み方)。

🔴 **PieFed 宛のタグ（`/dest/tags`・エントリのタグ）は、作成した投稿を編集して付ける（4.15.0・#1673）。**本文にもタイトルにも `#tag` は並べない。

- PieFed の投稿の作成（`POST /api/alpha/post`）はタグを受け取らず、**本文の `#tag` も拾わない**（ただの文字になる。4.14.0 の実投稿で確認）。受け取るのは編集（`PUT /api/alpha/post`）の `tags`（カンマ区切り・`#` なし）だけ。本家の 1.6.0 から変わっていない
- ＝ **1 件の投稿で要求が 2 本**（作成 → 編集）。⚠ 編集は連合へも流れる。タグの無いソースでは編集を出さない
- ⚠ **タグが付かなくても投稿は成功として数える**（もう出ているので、失敗にすると再実行で二重になる）。ログに warn `tags not attached`（`source` / `post_id` / `error`）が残る
- フレア（コミュニティごとに定義するラベル）は別物で、扱っていない
- ⚠ **投稿は出た直後から「編集済み」になる**（PieFed は編集で `edited_at` を必ず立てる）。作成と編集は別々に連合へ流れる
- ⚠ **タグの出どころはテンプレートに合わせる**: フィードのエントリは自分のタグ、本文を持つもの（テキスト・コマンド）はソースのタグ＋リモートのタグ付け、予定はソースのタグだけ
- 経緯: 4.13.0 までは同じソースの他の宛先しだい（単独ならタグなし・Mastodon / Misskey と併用なら本文とタイトルの両方・LINE と併用ならタグなし）。4.14.0（#1484）で「本文にだけ付ける」に揃えたが、PieFed 側でタグとして扱われなかった

#### Webhook 宛先の指定形式

`/dest/hooks` の各要素は **URL 文字列**か**オブジェクト**のどちらでもよい。オブジェクト形式は [matrix-webhook](https://github.com/tsunagal/matrix-webhook) 宛に送信先ルームを指定するためのもの。

```yaml
dest:
  hooks:
    - https://example.com/hook          # 従来どおりの URL 指定
    - url: https://example.com/webhook  # matrix-webhook 宛
      type: tsunagal
      channel: '#alerts:example.com'    # ルームエイリアス
    - url: https://example.com/webhook
      type: tsunagal
      room_id: '!AbCdEf:example.com'    # ルーム ID（channel との択一）
```

| キー | 必須 | 内容 |
|------|------|------|
| `url` | 必須 | 送信先 Webhook URL |
| `type` | 任意 | 宛先の種別。`tsunagal` のみ。省略すると Slack 互換の素の Webhook 扱い |
| `channel` | 任意 | ルームエイリアス（`#name:server` 形式） |
| `room_id` | 任意 | ルーム ID（`!xxxx:server` 形式） |

⚠ **スキーマが `additionalProperties: false` なので、この 4 つ以外のキーは書けない。**`config/schema/source.yaml` の `hooks` を参照。

⚠ **`channel` / `room_id` は matrix-webhook 側の解釈**で、`WebhookShrieker` はペイロードに載せるだけ。Slack / Discord / モロヘイヤ宛に書いても無視される。

##### `type: tsunagal` — Tsunagal（matrix-webhook）宛 (#1493)

🔴 **matrix-webhook は `text` / `channel` / `room_id` / `format` しか見ない。**未知のフィールドは黙って無視されるので、`WebhookShrieker` が積む `spoiler_text` は**エラーにもならずに落ちていた**。同じソースをモロヘイヤと matrix-webhook の両方へ流すと、**Matrix 宛だけ CW の内容が消える。**

`type: tsunagal` を書くと `TsunagalWebhookShrieker` が選ばれ、**CW を本文の先頭へ畳んで送る**（`spoiler_text` ＋ 空行 ＋ 本文）。⚠ **Matrix に CW の標準は無い**ので、これは独自の見せ方。

⚠⚠ **`type` を書かないと従来どおり CW は落ちる。**`room_id` の有無のような暗黙判定は**しない** — `channel` は Slack でも意味を持つので判定に使えず、「Matrix 固有なのは `room_id` だけ」という前提に乗ると、**`channel` だけで書かれた宛先（本番の 3 ソースがこの形）を取りこぼす**。

⚠ **クラス名が `Matrix～` でないのは意図的。**喋る相手は Matrix の Client-Server API ではなく `tsunagal/matrix-webhook` という HTTP webhook なので、`MatrixShrieker` は将来 C-S API を実装するときのために空けてある。

### 第三者が書ける URL を取りにいく経路 (#1666)

フィードの書き手（第三者）が決める URL を、tomato 自身が GET する経路は 2 つある。どちらも**取りにいく先のホストを検証する**（`Ginseng::PublicHost.validator`。初段もリダイレクトの各ホップも）。

| 経路 | 何を取りにいくか | 効くソース |
| --- | --- | --- |
| 添付（`RemoteAttachment`） | フィードの enclosure（先頭 4 件）を取り、投稿先へ上げる | `/dest/mastodon` / `/dest/misskey` の**直接経路**だけ。⚠ Webhook は `image_url` を渡すだけで、取りにいくのはモロヘイヤ側 |
| リモートのタグ付け（`Entry#nokogiri`） | エントリの URL のページ（h1〜h3 / title / meta のテキスト） | `/dest/mulukhiya/tagging/enable: true` のソース |

落ちるのは、IP アドレスのリテラル・ドットを含まない名前（`localhost`）・内部や予約アドレスに解決される名前・解決できない名前・それらへのリダイレクト。要求は 1 本も出ない。⚠ **`/etc/hosts` は見ない**（DNS だけ）。⚠ **名前解決の一時的な失敗も同じ扱いで、再送しない。**🔴 **プロキシ環境（`http_proxy` / `https_proxy`）では添付が全部落ち、リモートのタグ付けもソースのタグだけになる**（どちらも、検証したアドレスへ接続を固定できないため）。⚠ **IP アドレスを直に書いた画像 URL（`http://203.0.113.1/a.png`）も落ちる**（公開のアドレスでも）。

- 🔴 **取れなかった添付は落とし、本文は投稿する。**ログに warn `attachment dropped`（`source` / `shrieker` / `host` / `error`）が残る。⚠ 添付の失敗で投稿ごと落とすと、**enclosure に 1 本おかしな URL が混ざっただけでそのエントリが宛先に届かなくなる**（Entry は作成済みなので次の run でも拾われない）
- リモートのタグ付けが拒否されたら、ソースのタグだけで投稿する（ログに error）
- ⚠ **添付の検証は gem（ginseng-fediverse 6.0.0 以降）の既定。**tomato 側に自前の検証は置いていない＝版を戻すと守りも消える（`RemoteAttachmentTest` が赤くなる）

### モロヘイヤ連携

- `/dest/mulukhiya/enable` — モロヘイヤ経由の投稿（**既定は false**。`true` と書いたときだけ有効。`/dest/mulukhiya` を書くなら `enable` は必須）
- `/dest/mulukhiya/url`, `/dest/mulukhiya/tagging/enable` — ハッシュタグ自動付与
- Webhook digest・カスタムフィード連携の詳細: [mulukhiya-toot-proxy 連携ドキュメント](https://github.com/pooza/mulukhiya-toot-proxy/blob/develop/docs/tomato-shrieker-integration.md)

#### タグ処理の責務分担

- tomato-shrieker は `dest.tags` / `extra_tags` / モロヘイヤ remote_tagging で集めたタグを**そのまま投稿に乗せる**（短いタグも含めて素通し）
- 短いタグや表示上ノイズになるタグの除外はモロヘイヤ側の責務。短タグフィルタは表示・配信品質ポリシーが集まるあちら側で実装する
- v4.1.2 以前は `Source#create_tags` / `Entry#tags` に 2 文字以下を落とす `select!` が入っていたが、Ruby 4.0 で `Ginseng::Fediverse::TagContainer#delete` が無限再帰するインシデント (#1447) を機に削除した

#### Webhook digest の取り扱い (運用注意)

WebhookShrieker → モロヘイヤの URL は `POST /mulukhiya/webhook/{digest}` で、digest = `SHA256(SNS URI + OAuth トークン + 暗号化 salt)`。**3 要素のいずれかが変わると全 Webhook URL が無効になる** (モロヘイヤ #4106 / v5.2.1 で `/crypt/salt` 廃止試行 → 全投稿 404 のインシデント)。回帰テストはモロヘイヤ側の `test/unit/model/webhook_digest.rb`。

### CommandSource

- `/ruby/jit` — `true` なら CommandSource の子プロセスに `RUBY_YJIT_ENABLE=yes` を渡す。既定は `false`（本番は `local.yaml` で `yes`）
- ⚠ **v4.13.0 より前は既定値が無く、`local.yaml` に書いていない環境では CommandSource に触れた時点で `ConfigError` になっていた (#1614)**

### 暗号化

- `/crypt/password` — アクセストークン等の暗号化用パスワード（PieFedShrieker で使用）
- `bin/crypt.rb` で暗号化、`bin/decrypt.rb` で復号

### スケジュール形式

3形式から選択。指定方法は [rufus-scheduler](https://github.com/jmettraux/rufus-scheduler) に準じる。

| 形式 | キー | 例 |
|------|------|-----|
| 定期実行 | `/schedule/every` | `5m`, `1h`, `1d` |
| cron | `/schedule/cron` | `'0 6 * * *'` |
| 指定時刻 | `/schedule/at` | `'2026/5/18 18:00'` |
