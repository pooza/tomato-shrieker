# tomato-shrieker 開発ガイド

## プロジェクト概要

投稿のソース・投稿先・スケジュールの3要素を組み合わせた、単純なつぶやきボットエンジン。
複数のボットを1インスタンスで管理できる。

- **技術スタック**: Ruby 3.4 / Rufus::Scheduler / SQLite3 (Sequel ORM)
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
      → Scheduler.instance.exec (Rufus::Scheduler)
        → Source.all → register (各ソースをスケジューラに登録)
```

rake タスク (`rake start` / `rake restart`) は便利コマンドとして残っているが、systemd/rc.d からは bin スクリプトを直接呼ぶ。

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

## CI

GitHub Actions (`.github/workflows/test.yml`):

- Ruby 3.4.8 / Ubuntu
- `bundle exec rake migration:run` → `bundle exec rubocop`
- テストは `bundle exec rake test`（CI では DB マイグレーション後に実行）

## ディレクトリ構成（主要）

```text
app/lib/tomato_shrieker/
  source/         # データソース (7種)
  shrieker/       # 投稿先 (6種)
  daemon/         # SchedulerDaemon
  model/          # Entry (Sequel::Model)
  service/        # SlackService, MulukhiyaService
app/task/
  tomato/         # rake タスク (daemons, feed, calendar, command, text, source)
  migration.rb    # DB マイグレーション
bin/
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

## 4.0 計画

モロヘイヤや ginseng 系 gem の成果物を流用してきた経緯があり、モロヘイヤ 5.0 のアーキテクチャ更新も活用できる可能性がある。

### PieFed 対応の ginseng-piefed 移行

PieFed 対応は姉妹プロダクト mulukhiya-toot-proxy（モロヘイヤ）に由来する。モロヘイヤ側で PieFed 対応を ginseng-piefed gem として独立させる計画があり、tomato-shrieker でも PiefedShrieker を ginseng-piefed ベースに移行する。

- **現状**: PiefedShrieker は独自実装（HTTP クライアントで PieFed API を直接操作）
- **目標**: Mastodon/Misskey が ginseng-fediverse を基底にしているのと同様に、ginseng-piefed を基底クラスとする構成へ移行

### テンプレート取り回しの統一

Shrieker 間でテンプレートの扱いに差があり、特に PieFed 周りが煩雑。メジャーアップグレードで整理する。

- **Source/FeedSource にハードコードされた `:piefed` キー**: ベースクラスが特定の Shrieker を知っている（他の Shrieker は `:default` のみ）
- **フォールバックパスの不一致**: Source は `self['/dest/template']`、FeedSource は `self['/piefed/template']` と異なるパスにフォールバック
- **PiefedShrieker#search_template の二重処理**: Source 側でテンプレートを用意した上で、Shrieker 側でさらに再構築している

### Ruby 4.0 正式対応

Ruby 4.0 をサポート対象に加える。

### Sentry.io 導入

姉妹プロジェクト mulukhiya-toot-proxy・capsicum で成果を上げており、tomato-shrieker にも導入する。

### google-news-rss-cleaner 統合・インフラ構成の検討

google-news-rss-cleaner は tomato-shrieker との連携を目的としたツールだが、Node.js 製。

- **モノレポ案**: 連携が明確になるが、tomato-shrieker は FreeBSD 運用で、ヘッドレスブラウザの動作が困難なため逆に制約になりうる
- **Ubuntu 集約案**: google-news-rss-cleaner を運用している Ubuntu に tomato-shrieker も寄せる
- インフラ構成の判断を含む

### GoogleNewsSource 同一ニュース重複投稿の抑制

Google News では同じニュースが各社メディアから配信され、URL・タイトルが異なるため既存の DB 重複排除では検出できない。bigram Jaccard 係数による類似度判定で抑制する。

- **実装済み**: `GoogleNewsSource#ignore_entry?` で直近48時間の既存エントリと比較（閾値 0.4）
- **設定**: デフォルトオン、`/source/news/dedupe: false` でオフ可能

### テスト改善

現在のテストは mock/stub を使用しておらず、実際に外部 API へ投稿してしまう。テスト実行時に実投稿をスキップする仕組みを導入する。

### SQLite 並行アクセスの改善

`FeedSource#fetch` で複数スレッドから同時 INSERT しているが、WAL モード未設定・BusyException リトライ無制限など、並行処理の設定が不十分。

- WAL モード有効化
- busy_timeout 設定
- リトライ上限の追加

### Source 管理の改善

現状は YAML 手編集 + rake タスクの組み合わせ。

- **CLI 強化案**: 工数が少なく、現運用との親和性が高い
- **Web サービス新設案**: 過去に一度断念した長年の懸案。フロントエンド検討が増えるのが断念理由だったが、モロヘイヤの WebUI 設計に乗ることで工数を抑えられる可能性がある。外形監視ツールと組み合わせて監視しやすくなる利点もある

## 関連リポジトリ

- [ginseng-core](https://github.com/pooza/ginseng-core) — 基盤ライブラリ（branch: main）
- [ginseng-fediverse](https://github.com/pooza/ginseng-fediverse) — Fediverse 対応
- [ginseng-youtube](https://github.com/pooza/ginseng-youtube) — YouTube 対応
- [mulukhiya-toot-proxy](https://github.com/pooza/mulukhiya-toot-proxy) — 姉妹プロジェクト（構成が類似）
