# tomato-shrieker 開発ガイド

## プロジェクト概要

投稿のソース・投稿先・スケジュールの3要素を組み合わせた、単純なつぶやきボットエンジン。
複数のボットを1インスタンスで管理できる。

- **技術スタック**: Ruby 4.0 / Rufus::Scheduler / SQLite3 (Sequel ORM)
- **投稿先**: Mastodon, Misskey, LINE, PieFed, Nostr, Webhook (Slack, Discord等)
- **ginseng-\*系gem**: 自作フレームワーク。必要に応じて全て更新してよい

## ブランチ戦略

| ブランチ | 目的 |
| --- | --- |
| `master` | リリース済み安定版（デフォルト） |
| `develop` | 開発ブランチ。日常の作業はここで行う |

### リリースフロー

1. `develop` で開発・コミット
2. リリース時に `develop` → `master` へPRを作成しマージ
3. `master` でタグを打ちリリース: `gh release create vX.Y.Z --target master --title "X.Y.Z"`
4. `config/application.yaml` の `/shrieker/version` がバージョンの正本。リリース前に更新する
5. リリース直前に [release-validation.md](release-validation.md) の手順で各 Source / Shrieker の動作を手動検証する（CI では捕まらない統合系のリグレッション検出用）
6. セキュリティレビューは各マイルストーンの Issue をすべて消化した後、リリース直前に実施する
7. `docs/CLAUDE.md` のリリース済みセクションを更新する

### リリースノート

- セキュリティアップデート（gem のパッチ更新等）は、実質的に影響がなくてもリリースノートに記載する
- マイナーリリース: 通常の機能追加・改善
- パッチリリース: 致命的な不具合やセキュリティ修正時のみ

### Dependabot PR の取り扱い

`dependabot.yml` で `open-pull-requests-limit: 0` に設定しており、通常のバージョン更新PRは自動作成されない。**セキュリティアドバイザリ由来のPRのみ**が自動生成される（GitHub の仕様としてセキュリティアラートは `open-pull-requests-limit` の制限を受けない）。

対応フローは2パターン:

1. **未対応の場合**: PRをそのままマージする
2. **`bundle update` 等で対応済みの場合**: 「Already included via bundle update in commit xxxxx」とコメントしてクローズする

判断基準: Gemfile.lock の該当 gem バージョンが、PRで提示されたバージョン以上かどうかを確認する。

## アーキテクチャ

### 3要素モデル

```
Source (データソース) → Shrieker (投稿先) → Schedule (スケジュール)
```

### Source サブクラス

| クラス | 継承元 | 用途 |
|--------|--------|------|
| FeedSource | Source | RSS/Atom フィード (Feedjira) |
| CommandSource | Source | シェルコマンド出力 |
| TextSource | Source | 静的テキスト |
| GoogleNewsSource | FeedSource | Google News 検索 |
| GitHubRepositorySource | FeedSource | GitHub リリース/コミット |
| IcalendarSource | Source | カレンダーイベント (Google, iCloud等) |
| YouTubeChannelSource | FeedSource | YouTube チャンネル動画 |

### Shrieker サブクラス

| クラス | 基底 | 用途 |
|--------|------|------|
| MastodonShrieker | Ginseng::Fediverse::MastodonService | Mastodon/Pleroma |
| MisskeyShrieker | Ginseng::Fediverse::MisskeyService | Misskey |
| LineShrieker | Ginseng::LineService | LINE メッセージング |
| PiefedShrieker | (独自実装) | PieFed コミュニティ投稿 |
| NostrShrieker | (独自実装) | Nostr イベント |
| WebhookShrieker | SlackService | Webhook (Slack, Discord等) |

## デーモン管理

daemon-spawn gem は廃止済み（#1388）。`Ginseng::Daemon` はスタンドアロンクラスとしてフォアグラウンド実行する。デーモン化は OS の init システムに委任する。

- **FreeBSD (rc.d)**: `daemon(8)` でバックグラウンド化。stop は `bin/scheduler_daemon.rb stop`（PID ファイル経由で TERM 送信）
- **Linux (systemd)**: `Type=simple`、`ExecStop=/bin/kill -TERM $MAINPID`
- **デプロイ時**: rc.d スクリプト / systemd unit の更新が必要（[config/sample/](../config/sample/) 参照）

### 起動チェーン

```
systemd/rc.d → bin/scheduler_daemon.rb start
  → SchedulerDaemon.spawn! (Ginseng::Daemon)
    → SchedulerDaemon#start
      → Sequel.connect (SQLite3)
      → MonitorServer#start (Puma embedded / 監視用 HTTP)
      → Scheduler.instance.exec (Rufus::Scheduler)
        → Source.all → register (各ソースをスケジューラに登録)
```

systemd/rc.d からは bin スクリプトを直接呼ぶ。`rake start` / `rake restart` は廃止済み（#1410）。

## 監視 (Kuma 連携)

scheduler_daemon と同一プロセス内に Puma 埋め込みの軽量 HTTP サーバを同居させ、Kuma 等の外形監視ツールから叩ける HTTP エンドポイントを提供する。UI は持たず、Kuma のダッシュボードが一次情報となる設計。

### エンドポイント

| パス | 用途 | 応答 |
|------|------|------|
| `/healthz` | 総合ヘルスチェック | 200 / 503 |
| `/healthz/source/:id` | ソース別ヘルスチェック | 200 / 503 / 404 |
| `/status.json` | 全体ステータス（人間/ダッシュボード向け） | 200 (JSON) |

#### `/healthz` の判定

scheduler プロセス生存 + DB 接続 + Rufus ジョブが 1 件以上、すべて満たせば 200。いずれかが NG なら 503。

#### `/healthz/source/:id` の判定

該当ソースの最終実行 (`source_run_log` の最新行) が以下の両方を満たせば 200:

- 最終実行から `tolerance_seconds` 以内に走っている (stale でない)
- 直近実行が成功している (error でない)

ソースが存在しない場合は 404。`/schedule/at` の単発ソースは監視対象外として常に 200 を返す。

#### `/status.json` の中身

```json
{
  "scheduler": true,
  "database": true,
  "sources": [
    {
      "id": "matrix-news",
      "class": "TomatoShrieker::FeedSource",
      "schedule": {"type": "every", "value": "5m"},
      "tolerance_seconds": 600,
      "last_run_at": "2026-04-14T14:00:00+09:00",
      "last_status": "success",
      "last_error": null,
      "last_duration_ms": 423
    }
  ]
}
```

Kuma からは見ない（人間が `curl | jq` する用、または外部ダッシュボードに食わせる用）。

### 設定

| キー | 既定値 | 意味 |
|------|--------|------|
| `/monitor/enabled` | `true` | `false` で監視サーバの起動をスキップ |
| `/monitor/bind` | `127.0.0.1` | バインドアドレス |
| `/monitor/port` | `4567` | リッスンポート |
| `/monitor/default_tolerance_seconds` | `7200` | period 不明時のフォールバック tolerance |
| `/monitor/retention_days` | `14` | source_run_log の保持日数（自動 prune） |

ソースごとに `/monitor/tolerance` を上書き可（文字列なら `'30m'` のような Rufus 形式、数値なら秒）。デフォルトは `period × 2`。

### 実行ログテーブル `source_run_log`

各 source の Rufus ジョブが発火するたびに INSERT される（`migration/009`）:

- `source_id`, `executed_at`, `status` (`success` | `error`), `error_message`, `duration_ms`
- 古いレコードは Rufus ジョブで毎日 prune（`/monitor/retention_days`）

`Source#schedule` のラッパで成功/失敗を記録するため、CLI からの `bin/shrieker` 直接実行や rake タスクは記録対象外（スケジューラ起因の稼働だけを監視する設計）。

### Kuma の登録例

```
HTTP(s) Monitor:
  Name: tomato-shrieker
  URL: http://<host>:4567/healthz
  Interval: 60s
  Accepted Status Codes: 200-299
```

ソース別に追跡したい場合は `http://<host>:4567/healthz/source/<source-id>` を別モニターとして追加する。

### 運用: 監視ホストから tomato-shrieker への到達経路

`/monitor/bind` のデフォルトは `127.0.0.1` で、外向けには公開されない。監視ホスト (Kuma 等) から /healthz を叩く経路は環境に応じて選択する:

| 方式 | Pros | Cons / 注意点 |
|------|------|----------------|
| **Tailscale** | お手軽、ACL 一式、暗号化、NAT 越え | FreeBSD では Tier 2 扱い (`pkg install tailscale`、ports `net/tailscale`)。userspace で動くがカーネル統合はない |
| **WireGuard** | ネイティブ、軽量、FreeBSD は kernel module あり | ACL 等は別途 |
| **Reverse SSH tunnel** | 既存の SSH 鍵運用に乗せられる | tunnel プロセスの監視が別途必要 |
| **同一ホストに Kuma 同居** | ネットワーク経路ゼロ、127.0.0.1 で完結 | Kuma の UI を見る側で別途 SSH ポートフォワード等が必要 |
| **Firewall + IP 制限** | VPN 不要 | 監視ホストの固定 IP が前提。bind を 0.0.0.0 にする必要あり |

本番の seas (FreeBSD) では Tailscale を併用する想定。Tailscale が動かない場合でも上記の代替で詰まないため、監視機能の有無で OS サポート判断を変える必要はない。

## 重要な設計判断

### CommandSource の子プロセス実行

`Bundler.with_unbundled_env` で囲む（親の RUBYOPT, GEM_HOME 等の漏洩防止）。
ただし `command.env['BUNDLE_GEMFILE']` は引き続き必要（with_unbundled_env で一掃された後、子プロセスに正しい Gemfile 位置を教える役割）。

### ginseng-\* gem のデフォルトブランチ

全て `main` に統一済み。Gemfile で `branch: 'main'` を明示指定する。

## 設定構造

- `config/application.yaml` — デフォルト設定
- `config/local.yaml` — ローカル上書き（git 管理外）
- `config/sources/*.yaml` — ソース定義（動的読み込み）
- `config/schema/base.yaml` — JSON Schema によるバリデーション

設定アクセスは Ginseng のスラッシュ記法: `config['/path/to/key']`

## ソース定義 YAML リファレンス

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
| GoogleNewsSource | `/source/news/phrase` | FeedSource の設定項目も利用可。`/source/news/dedupe`（デフォルト true） |
| IcalendarSource | `/source/icalendar/url` | iCalendar (.ics) URL。`/source/icalendar/keyword` |
| YouTubeChannelSource | `/source/youtube_channel/channel_id` | `/source/youtube_channel/keyword` |
| GitHubRepositorySource | `/source/github/repository` | `/source/github/timeline`（releases 等） |

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
| WebhookShrieker | `/dest/hooks` | Slack Incoming Webhooks 互換 URL の配列（Discord は末尾に `/slack`） |
| LineShrieker | `/dest/line/user_id`, `/dest/line/token` | チャンネルアクセストークン（長期） |
| PieFedShrieker | `/dest/piefed/url`, `/dest/piefed/access_token`, `/dest/piefed/community_name` | `/dest/piefed/api_version`（デフォルト alpha） |
| NostrShrieker | `/dest/nostr/private_key` | nsec 形式対応。リレーは `/nostr/relays`（application.yaml） |

### モロヘイヤ連携

- `/dest/mulukhiya/enable` — モロヘイヤ経由の投稿（デフォルト true）
- `/dest/mulukhiya/url`, `/dest/mulukhiya/tagging/enable` — ハッシュタグ自動付与
- Webhook digest・カスタムフィード連携の詳細: [mulukhiya-toot-proxy 連携ドキュメント](https://github.com/pooza/mulukhiya-toot-proxy/blob/develop/docs/tomato-shrieker-integration.md)

### 暗号化

- `/crypt/password` — アクセストークン等の暗号化用パスワード（PieFedShrieker で使用）
- `bin/crypt.rb` で暗号化、`bin/decrypt.rb` で復号

### 例外通知

- `/slack/hooks` — 例外発生時の通知先（Slack 互換 Webhook URL の配列）

### スケジュール形式

3形式から選択。指定方法は [rufus-scheduler](https://github.com/jmettraux/rufus-scheduler) に準じる。

| 形式 | キー | 例 |
|------|------|-----|
| 定期実行 | `/schedule/every` | `5m`, `1h`, `1d` |
| cron | `/schedule/cron` | `'0 6 * * *'` |
| 指定時刻 | `/schedule/at` | `'2026/5/18 18:00'` |

## CI

GitHub Actions (`.github/workflows/test.yml`):

- Ruby 4.0 / Ubuntu
- `bundle exec rake migration:run` → `bundle exec rubocop` → `bundle exec rake test`

## ディレクトリ構成（主要）

```text
app/lib/tomato_shrieker/
  source/         # データソース (7種)
  shrieker/       # 投稿先 (6種)
  daemon/         # SchedulerDaemon
  model/          # Entry (Sequel::Model)
  service/        # SlackService, MulukhiyaService
  cli/            # CLI コマンド (Thor)
app/task/
  migration.rb    # DB マイグレーション
  bundle.rb, config.rb, test.rb  # ビルド系 rake タスク
bin/
  shrieker             # CLI エントリポイント (source list/fetch/shriek/touch/clear)
  scheduler_daemon.rb  # デーモンエントリポイント
config/
  application.yaml     # メイン設定
  sources/             # ソース定義 YAML
  sample/              # systemd/rc.d サンプル
views/                 # ERB テンプレート (common, title, calendar, summary等)
test/                  # テストファイル
```

## コーディング規約

- RuboCop に準拠（`.rubocop.yml`）
- テスト: test-unit (`TomatoShrieker::TestCase` 基底クラス)
- 文字列: シングルクォート
- メソッド末尾でも `return` を省略しない
- 行長: 100文字（テストファイルは除外）
- 末尾カンマ: 複数行では付与

## 運用ルール

### Sentry コメント運用

Sentry イシューをクローズせず経過観察とする場合、その意図を Sentry イシューのコメントに記録する。「経過観察」「再発待ち」「次バージョンで対応予定」など、クローズしない理由を明記し、単なる放置と区別できるようにする。

### Nostr のテスト責任

Nostr 対応は外部ユーザーのリクエストで実装された機能。動作確認・テストの責任はリクエスト元ユーザーが負う（伝達済み）。不具合があれば対応するが、積極的なテストは行わない。

## 4.0 計画

詳細は `docs/v4-plan.md` を参照。以下は概要と実装状況。

### 実装済み

- daemon-spawn 廃止 → `Ginseng::Daemon` フォアグラウンド実行
- GoogleNewsSource 重複投稿抑制（bigram Jaccard 係数）
- SQLite 並行アクセス改善（WAL モード・busy_timeout・リトライ上限）
- Nostr nsec 対応
- FreeBSD 起動スクリプト更新（stop の pkill フォールバック）
- テンプレート取り回しの統一（**破壊的変更**）
- PieFed 対応の ginseng-piefed 移行
- テスト改善（mock/stub 導入、webmock）
- Sentry.io 導入
- Ruby 4.0 移行
- CI 改善（テスト実行追加、Ruby 4.0 化、actions/checkout v4）
- CLI 新設と rake タスク整理（#1410）— Thor ベースの `bin/shrieker` を導入、ソース系 rake タスクと start/stop/restart を廃止

### 未着手

- #1429 CLI: ソース YAML 操作サブコマンド (add/edit/delete/validate)
- #1430 ginseng-core `Config#errors` の検証対象を merged config に修正（schema 不整合の根治）
- #1407 GitHub Wiki の最新化と docs ↔ Wiki 整理
- #1416 監視（簡易 Web インターフェース + Kuma 連携）
- デフォルトブランチを `master` → `main` に変更（リリース時）

### 4.0 破壊的変更（リリースノート・Wiki 記載必須）

- **テンプレート取り回しの統一 (#1398)**: Source/FeedSource/IcalendarSource の `templates` から `:piefed` キーを除去。`/dest/piefed/template` 未設定時のフォールバックが `:default` テンプレートに変更。PieFed 投稿で明示的にテンプレートを設定していないユーザーは投稿フォーマットが変わる可能性あり

## セッション開始時の同期手順

会話の最初に「進捗を同期してください」等の指示があった場合、以下の手順を実行する。

### 1. プロジェクトガイドの読み込み

- `docs/CLAUDE.md` を読む（プロジェクトのルール・構造・履歴の正本）
- `MEMORY.md` は自動ロードされるので、両者の整合性を意識する

### 2. リモートとの同期・状態確認

- `git fetch origin` — **最初に必ず実行**。リモートが正本であり、ローカルの状態を信用しない
- `git log HEAD..origin/develop --oneline` — リモートに未取り込みのコミットがないか確認。差分があればpullを検討
- `git log --oneline -10` — 直近のコミット履歴
- `gh issue list --state open` — open Issue一覧
- `gh pr list --state open` — open PR一覧

### 3. Dependabotセキュリティアラート

- `gh api repos/pooza/tomato-shrieker/dependabot/alerts` で open アラートを確認
- 0件なら対応不要、あれば提案

### 4. Codexレビューコメントの確認

- 最近マージされたPR（`gh pr list --state merged --limit 5`）を取得
- 各PRに対して `gh api repos/pooza/tomato-shrieker/pulls/{number}/comments` でCodex（`chatgpt-codex-connector[bot]`）のコメントを確認
- 未返信のコメントがあれば内容を確認し、対応が必要か判断

### 5. Sentry の新規イシュー確認

- `sentry-cli issues list` で未解決イシューを確認する（`~/.sentryclirc` に認証トークンとデフォルトプロジェクトが設定済み）
- 各イシューの過去コメント（対応経緯）を確認する: `curl -sH "Authorization: Bearer $TOKEN" https://sentry.io/api/0/issues/{issue_id}/comments/ | python3 -m json.tool`
- 新規・未解決のイシューがあれば内容を確認し、対応が必要か判断する（対応が必要なら GitHub Issue を起票）
- 判断結果や対応経緯はコメントとして記録する: `curl -sX POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"text":"コメント内容"}' https://sentry.io/api/0/issues/{issue_id}/comments/`
- `$TOKEN` は `~/.sentryclirc` の `[auth]` セクションから取得する
- Sentry 未導入のプロジェクトではこのステップをスキップする

### 6. 外部リポジトリの同期確認

> **TODO**: chubo2 インフラノート（`pooza/chubo2` の `docs/infra-note.md`）との連携が整ったタイミングで手順を追加する。

### 7. マイルストーンの状態確認

- `docs/CLAUDE.md` と MEMORY.md に記載された次期マイルストーンの Issue が、実際の GitHub 上の状態（open/closed）と一致しているか確認
- クローズ済みの Issue があれば MEMORY.md から除外し、`docs/CLAUDE.md` も必要に応じて更新

### 8. MEMORY.md の更新

- 上記で検出した差分（Issue 状態、リリース日の誤り、件数のズレ等）を反映

### 9. 同期結果の報告

- 現在のブランチ・状態、マイルストーンの状況、各確認項目の結果をまとめて報告する

## 情報の記載先ルール

- **課題・タスク** → GitHub Issue で管理
- **プロジェクト共有すべき知見** → `docs/CLAUDE.md` など git 管理下のファイルに記載
- **進捗の同期** → `MEMORY.md` だけでなく `docs/CLAUDE.md` も更新すること。特にリリース済みバージョンの反映（「開発中」→「リリース済み」への変更）を忘れないこと

## 関連リポジトリ

- [ginseng-core](https://github.com/pooza/ginseng-core) — 基盤ライブラリ（branch: main）
- [ginseng-fediverse](https://github.com/pooza/ginseng-fediverse) — Fediverse 対応
- [ginseng-youtube](https://github.com/pooza/ginseng-youtube) — YouTube 対応
- [mulukhiya-toot-proxy](https://github.com/pooza/mulukhiya-toot-proxy) — 姉妹プロジェクト（構成が類似）
