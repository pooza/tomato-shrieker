# ソース定義 YAML リファレンス

⚠ **`config/sources/*.yaml` の正本。**⚠⚠ **実体は gitignore されていて oscura にしか無い。**

各ソースは `config/sources/*.yaml` にファイル単位で定義する。ソースごとにファイルを分けて管理できる（例: `config/sources/news.yaml`, `config/sources/blog.yaml`）。起動時にディレクトリ内の全 YAML を動的に読み込む。

基本構造:

```yaml
sources:
  - id: optional-unique-id  # 省略時は設定全体のダイジェスト
    source:
      # ソース固有の設定
    schedule:
      every: 1h             # every / cron / at のいずれか
    dest:
      # 投稿先固有の設定
      tags:                  # ハッシュタグ（先頭の # を除いた文字列の配列）
        - tag1
      template: default      # ERB テンプレート名（views/ 配下）
```

### Source 設定項目

| Source | 主要キー | 備考 |
|--------|----------|------|
| TextSource | `/source/text` | 定型文 |
| CommandSource | `/source/command` | 文字列（sh経由）または配列（shellescape）。`/source/dir`, `/source/env`, `/source/delimiter`（デフォルト `=====`） |
| FeedSource | `/source/feed`（`/source/url` でも可） | `/source/title/unique`（デフォルト true）、`/keep/years`、`/dest/prefix`、`/dest/account/bot` |
| GoogleNewsSource | `/source/news/phrase` | FeedSource の設定項目も利用可。`/source/news/dedupe`（デフォルト true）。`/google/news/cleaner/url` を application.yaml に設定すると [google-news-rss-cleaner](https://github.com/pooza/google-news-rss-cleaner) 経由で実記事 URL に解決し、Google News が古記事に付ける fresh pubDate 問題も併せて回避する |
| IcalendarSource | `/source/icalendar/url` | iCalendar (.ics) URL。`/source/icalendar/keyword` |
| YouTubeChannelSource | `/source/youtube_channel/channel_id` | `/source/youtube_channel/keyword` |
| GitHubRepositorySource | `/source/github/repository` | `/source/github/timeline`（releases 等） |

🔴 **CommandSource に資格情報を渡すなら `/source/env` に書く (#1623)。**`/source/env` の値は、キー名を見ずに全部がログ（`"command":` / `"env":`）と失敗時の例外メッセージから伏せられる。宛先の資格情報（`/dest/hooks` の URL・`/dest/mastodon/token` など）も同じく伏せる。⚠ **`/source/command` の中に直接書いた資格情報は、上のどれとも一致しなければ伏せられない**（webhook URL や Uptime Kuma の push URL はトークンがパスに入るので、上流のキー名・URL のマスクでも拾えない）。⚠ 8 文字未満の値は伏せない（`DEBUG: '1'` まで伏せると、ログの同じ文字が全部 `[FILTERED]` になって読めなくなる）。⚠⚠ **伏せるのは「書いたとおりの形」（とシェルエスケープした形）だけ。**コマンドが加工して書き出した形（URL のパスだけ・クエリを落とした URL・JSON や HTML のエスケープ・URL エンコード・Base64・途中で折り返された値）は伏せられない。

### キーワードフィルタ（FeedSource 系共通）

- `/source/keyword` — 含むエントリのみ対象（正規表現可）
- `/source/negative_keyword` — 含まないエントリのみ対象（正規表現可）

### マルチエントリ（FeedSource）

- `/dest/multi_entries` — true で直近記事をまとめて投稿（Hexo 対応）
- `/dest/category` — カテゴリで絞り込み
- `/dest/limit` — 最大記事数（デフォルト 5）

### Shrieker 設定項目

| Shrieker | 主要キー | 備考 |
|----------|----------|------|
| MastodonShrieker | `/dest/mastodon/url`, `/dest/mastodon/token` | 権限: `write:statuses`（画像は `write:media`）。`/dest/visibility` |
| MisskeyShrieker | `/dest/misskey/url`, `/dest/misskey/token` | 権限: `write:notes`（画像は `write:drive`） |
| WebhookShrieker | `/dest/hooks` | Slack Incoming Webhooks 互換の宛先の配列（Discord は末尾に `/slack`）。URL 文字列のほかオブジェクト形式も可 → [Webhook 宛先の指定形式](#webhook-宛先の指定形式) |
| LineShrieker | `/dest/line/user_id`, `/dest/line/token` | チャンネルアクセストークン（長期） |
| PieFedShrieker | `/dest/piefed/host`, `/dest/piefed/user_id`, `/dest/piefed/password`, `/dest/piefed/community_id` | `host` はホスト名だけ（接続先は常に `https://<host>`）。`/dest/piefed/template`。API の版は `config/local.yaml` の `/piefed/api/version`（デフォルト alpha） |
| NostrShrieker | `/dest/nostr/private_key` | nsec 形式対応。リレーは `/nostr/relays`（application.yaml） |

🔴 **宛先はリダイレクトを追わない（4.14.0・ginseng-core 2.0.0）。宛先の URL は `https://` の最終オリジンで書く。**宛先が 3xx を返すと、その配信は `Ginseng::GatewayError: Bad response 301`（など）で失敗する。これまでは 301 / 302 を追って GET に化け、本文が落ちたまま「成功」と数えていた。⚠ `bin/shrieker source validate` は `/dest/hooks`・`/dest/mastodon/url`・`/dest/misskey/url` が `http://` のとき WARN を出す（`disable: true` の定義には出さない）。読み方は [monitoring.md](monitoring.md#bad-response-3xx-の読み方)。

⚠ **PieFed 宛は、本文にだけタグ（`/dest/tags`）を付け、タイトルには付けない（4.14.0・#1484）。**4.13.0 までは同じソースの他の宛先しだいだった（単独ならタグなし・Mastodon / Misskey と併用なら本文とタイトルの両方・LINE と併用ならタグなし）。

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

### モロヘイヤ連携

- `/dest/mulukhiya/enable` — モロヘイヤ経由の投稿（デフォルト true）
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
