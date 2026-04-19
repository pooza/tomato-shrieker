# tomato-shrieker v4.0 計画

**作成日**: 2026-03-14

## 目標

- テンプレート・PieFed 周りのアーキテクチャを整理し、Shrieker 間の非対称性を解消する
- GoogleNewsSource の実用性向上（重複投稿抑制、google-news-rss-cleaner 連携）
- テスト基盤の改善により、安全にテストを実行できる環境を整える
- SQLite の並行アクセス周りを堅牢化する
- Ruby 4.0 への移行、Sentry.io 導入など、基盤の現代化を進める
- CLI 新設による Source 管理の改善と、rake タスク構成の整理

## ブランチ・リリース戦略

| バージョン | ブランチ | 目的 |
|-----------|---------|------|
| 3.x | `main` | 現行安定版（4.0 リリース後は廃止） |
| 4.0 | `develop` → `main`（デフォルトブランチ変更） | アーキテクチャ整理・基盤更新 |

### リリース時の作業

- デフォルトブランチを `main` に変更（2026-04-19 完了）
- 全機能が残存するため、3.x 系のメンテナンスブランチは不要
- 破壊的変更を含むメジャーアップグレードだが、ソース定義 YAML の互換性は維持する

## 1. テンプレート取り回しの統一

**Issue**: #1398

### 現状の問題

- Source/FeedSource に `:piefed` キーがハードコードされており、ベースクラスが特定の Shrieker を知っている
- フォールバックパスが不統一（`self['/dest/template']` vs `self['/piefed/template']`）
- PiefedShrieker#search_template で Source 側のテンプレートを再構築する二重処理が発生

### 方針

- テンプレート解決を Shrieker 側に移し、Source はテンプレート名の提供のみに責務を限定する
- `:piefed` のような Shrieker 固有キーを Source から除去し、汎用的な仕組みに置き換える
- 各 Shrieker が自身のテンプレートを自律的に解決する構造にする

## 2. PieFed 対応の ginseng-piefed 移行

**Issue**: #1399

### 現状の問題

- PiefedShrieker は独自実装（HTTP クライアントで PieFed API を直接操作）
- Mastodon/Misskey が ginseng-fediverse を基底にしているのと非対称

### 方針

- mulukhiya-toot-proxy 側で PieFed 対応を ginseng-piefed gem として独立させる計画がある
- ginseng-piefed の完成後、PiefedShrieker の基底クラスを ginseng-piefed に移行する
- テンプレート統一（#1398）と合わせて進める

### 依存関係

- ginseng-piefed gem の開発完了が前提（mulukhiya-toot-proxy 側のタスク）

## 3. GoogleNewsSource の改善

### 3.1 同一ニュース重複投稿の抑制

**Issue**: #1401（実装済み・コミット済み）

Google News では同じニュースが各社メディアから配信され、URL・タイトルが異なるため既存の DB 重複排除では検出できない。

**実装内容**:

- タイトル末尾のメディア名（`- ITmedia` 等）を除去して正規化
- bigram（2文字組）の Jaccard 係数で直近48時間の既存エントリと類似度を判定（閾値 0.4）
- `GoogleNewsSource#ignore_entry?` をオーバーライドして実装
- デフォルトオン、`/source/news/dedupe: false` でオフ可能

完全な検出は困難だが、「大体取れればよい」性格の機能として割り切る。

### 3.2 google-news-rss-cleaner 連携

**関連リポジトリ**: [google-news-rss-cleaner](https://github.com/pooza/google-news-rss-cleaner)

Google News RSS の redirect URL を実記事 URL に解決する Node.js ツール。tomato-shrieker とは別リポ・疎結合で連携する。

**方針**:

- tomato-shrieker 側に google-news-rss-cleaner のエンドポイントを設定できる仕組みを追加
- GoogleNewsSource の `uri` メソッドで、設定に応じて google-news-rss-cleaner 経由のフィード取得に切り替え
- google-news-rss-cleaner 側にも tomato-shrieker の変更に応じた修正が発生しうるが、疎結合により最小限に抑える

**インフラ構成**:

```
FreeBSD / tomato-shrieker → HTTP → Ubuntu / google-news-rss-cleaner → Google News
```

- インフラは FreeBSD + Ubuntu の2台構成を維持
- モノレポ化・Ubuntu 集約は行わない

## 4. テスト改善

**Issue**: #1402

### 現状の問題

- mock/stub が一切使われておらず、全 Shrieker テストが実際に外部 API へ投稿する
- `test?` フラグで対象ソースを絞っているが、投稿自体は本物
- CI では rubocop とマイグレーションのみ実行し、テスト本体は実行していない

### 方針

- テスト実行時に Shrieker の実投稿をスキップし、テンプレート展開までで止める仕組みを導入する
- webmock 等による外部 HTTP リクエストの stub 化を検討
- CI でテスト本体を安全に実行できるようにする

## 5. SQLite 並行アクセスの改善

**Issue**: #1403

### 現状の問題

- `FeedSource#fetch` で `Parallel.each(in_threads: CPU*2)` により複数スレッドから同時 INSERT している
- WAL モード未設定（デフォルトの journal_mode DELETE）で、書き込みロック競合が起きやすい
- `Entry.create` の `rescue SQLite3::BusyException` → `retry` に上限がなく、無限ループの可能性
- `busy_timeout` 未設定

### 方針

- `Sequel.connect` 後に `PRAGMA journal_mode=WAL` を実行（読み書き並行性が大幅改善）
- `PRAGMA busy_timeout=5000` を設定
- `BusyException` リトライに上限（5回程度）を追加

## 6. CLI 新設と rake タスク整理

**Issue**: #1410

### 現状の問題

- Source 管理が YAML 手編集 + rake タスクの組み合わせで、操作性が悪い
- rake はタスク一覧の表示だけでもアプリ全体をロード + DB 接続するため、約1.3秒のオーバーヘッドがある
- ソース操作（list, fetch, touch, clear, shriek）と、ビルド系タスク（migrate, test）が混在している

### 方針

#### 6.1 CLI 新設

`bin/shrieker` 等の軽量コマンドを新設し、Source 管理操作を移す。

- `config/sources/` のファイル単位操作を前提とする
- YAML ファイルの操作 + JSON Schema バリデーションのみで、アプリ全体のロードを不要にする
- 新規サブコマンド: `list`, `add`, `edit`, `delete`, `validate`
- 既存 rake タスクからの移行: `fetch`, `shriek`, `touch`, `clear`（DB アクセスが必要なものはアプリロードを行うが、起動パスを最適化）
- `local.yaml` の `sources:` 互換性は残す（Config 変更なし）。CLI の恩恵を受けるには `config/sources/` への移行が必要
- `bin/migrate_sources.rb` を移行スクリプトとして提供（推奨だが必須ではない）

#### 6.2 rake タスク整理

rake にはビルド・インフラ系タスクのみ残す。

**残すもの**:

| タスク | 用途 |
|--------|------|
| `migrate` / `migration:run` | DB マイグレーション |
| `test` | テスト実行 |
| `bundle:update` / `bundle:check` | gem 管理 |
| `config:lint` | 設定バリデーション |

**CLI に移すもの**:

| 現タスク | CLI サブコマンド |
|---------|----------------|
| `tomato:source:list` | `shrieker source list` |
| `tomato:source:<name>:fetch` | `shrieker source fetch <name>` |
| `tomato:source:<name>:shriek` | `shrieker source shriek <name>` |
| `tomato:source:<name>:touch` | `shrieker source touch <name>` |
| `tomato:source:<name>:clear` | `shrieker source clear <name>` |

**廃止するもの**:

| タスク | 理由 |
|--------|------|
| `start` / `stop` / `restart` | systemd / rc.d に委任（daemon-spawn 廃止に伴い） |

## 7. daemon-spawn 廃止と起動スクリプト更新

**Issue**: #1388（実装済み・コミット済み）, #1309

### 実装済みの内容

- daemon-spawn gem を廃止し、`Ginseng::Daemon` でフォアグラウンド実行
- デーモン化は OS の init システム（systemd / rc.d）に委任

### FreeBSD 起動スクリプト更新

mulukhiya-toot-proxy の成果を流用し、stop の堅牢化を取り込む。

**変更内容**:

- stop 時に `pkill` でプロセスを確実に終了させる処理を追加
- エラー出力の抑制（`2>/dev/null`）

## 8. Sentry.io 導入

### 方針

mulukhiya-toot-proxy で確立したパターンをそのまま移植する。

**実装内容**:

- Gemfile に `gem 'sentry-ruby'` を追加（`sentry-sidekiq` は不要）
- `SchedulerDaemon#start` の `Sequel.connect` 直後に Sentry 初期化
- 設定は `/sentry/dsn` で管理（未設定時はスキップ）

```ruby
Sentry.init do |config|
  config.dsn = config['/sentry/dsn']
  config.release = Package.version
  config.environment = Environment.type
end
```

## 9. Ruby 4.0 移行

### 方針

単純にバージョンを上げる。並行サポートは不要。

**作業内容**:

- `.ruby-version` を 4.0 系に更新
- CI の Ruby バージョンを更新
- Gemfile の Ruby バージョン指定を確認（現在 `'>= 3.4', '< 5.0'` で対応済み）
- ginseng-* gem の Ruby 4.0 動作確認
- テスト実行による互換性検証

## 10. Nostr nsec 対応

**Issue**: #1375

Nostr の秘密鍵として nsec 形式（bech32 エンコード）をサポートする。

## 11. 監視

Source 管理の CLI 化（#6）とは別課題として、稼働状況の監視を整備する。

### 方針

- 外形監視は Kuma を運用中。Kuma から叩けるヘルスチェックの仕組みを提供する
- Sentry.io（#8）でエラー監視をカバー
- 「投稿が止まっている」等の正常系の監視のため、監視専用の簡易 Web インターフェースを検討する

### 簡易 Web インターフェース

- Source 管理 UI ではなく、監視のみを目的とした軽量なもの
- 各ソースの最終投稿時刻、エラー状態等をダッシュボード表示
- Kuma のヘルスチェックエンドポイントを兼ねる

## 12. CI 改善

### 現状

- CI は `rubocop` と `migration:run` のみ実行
- テスト本体（`rake test`）は CI で実行されていない
- Ruby バージョンは 3.4.8

### 方針

- テスト改善（#4）と合わせ、CI でテスト本体を実行できるようにする
- Ruby 4.0 に更新
- `actions/checkout` を v3 → v4 に更新
- bundler バージョンを現行に合わせる

**目標の CI ステップ**:

1. checkout
2. Ruby セットアップ（4.0.x）
3. apt install（libsqlite3-dev）
4. bundle install
5. migration:run
6. rubocop
7. rake test

## 13. GitHub Wiki の最新化と docs ↔ Wiki 整理

**Issue**: #1407

### Wiki の現状

- Wiki の実質的な内容更新は 2022-12 が最後
- NostrShrieker、GitHubRepositorySource のページが未作成
- ツイートタイムラインソース（Twitter）が廃止済みなのに残存
- IcalendarSource・YouTubeChannelSource の設定例が実装と不一致
- 動作環境の Ruby バージョンが古い

### 方針

#### docs と Wiki の役割分担

| 置き場 | 内容 |
|--------|------|
| docs/CLAUDE.md | 開発時に頻繁に参照する情報（アーキテクチャ、規約、設定項目一覧） |
| Wiki | ユーザー向けセットアップガイド、各機能の設定例、運用手順 |

#### Wiki → docs への転記

- 各ソース・Shrieker の設定項目一覧（開発時の参照頻度が高い）
- スケジュール形式（at / every / cron）の仕様

#### docs → Wiki への移動（アーカイブ）

- 詳細な設計経緯・実装メモのうち、日常開発で参照頻度が低いもの

#### Wiki の更新作業

- ページ新規作成: NostrShrieker、GitHubRepositorySource
- 廃止ページの整理: ツイートタイムラインソース
- 既存ページの更新: 動作環境、設置の手順（systemd/rc.d）、設定例の修正
- _Sidebar.md の更新

## 14. リリース手順

mulukhiya-toot-proxy の運用を踏襲する。

### リリース時の作業チェックリスト

- [ ] バージョン番号を決定（`config/application.yaml` の `/shrieker/version`）
- [ ] `develop` → `main` へ PR を作成しマージ
- [ ] `gh release create vX.Y.Z --target main --title "X.Y.Z"` でリリース作成
- [ ] docs/CLAUDE.md 更新（リリース済みセクションに追記）
- [ ] Wiki の関連ページ更新確認
- [ ] 本番サーバーへのデプロイ
- [ ] Codex レビューコメント確認（マージ後遅れて届く場合がある）
- [ ] デプロイ後の動作確認

### GitHub Codex レビュー

- PR マージ後に Codex（chatgpt-codex-connector[bot]）のレビューコメントが遅れて届くことがある
- セッション開始時に最近マージされた PR のレビューコメントを確認する
- 未対応の有益な指摘があれば対応し、対応内容をコメントで返信する

### セキュリティレビュー

- リリース前に Codex によるセキュリティレビューを実施
- 指摘事項はリリース前に対応する

### バージョニング方針

- **パッチリリース**（4.0.x 等）は致命的な不具合時のみ
- **通常の機能追加・改善はマイナーバージョン**（4.1.0 等）でまとめてリリース

## タスク一覧

### 実装済み

- [x] #1388 daemon-spawn gem 廃止
- [x] #1401 GoogleNewsSource 重複投稿抑制
- [x] #1375 Nostr nsec 対応
- [x] #1309 FreeBSD 起動スクリプト更新（stop の pkill フォールバック追加）
- [x] #1403 SQLite 並行アクセス改善（WAL モード・busy_timeout・リトライ上限）
- [x] WebhookShrieker Webhook URL ログ出力削除（Codex レビュー指摘対応）
- [x] モロヘイヤ連携ドキュメントへのリンク追加

### 4.0 リリースに必要（着手順）

- [x] Sentry.io 導入
- [x] #1402 テスト改善（mock/stub 導入）
- [x] #1398 テンプレート取り回しの統一
- [x] #1399 PieFed 対応の ginseng-piefed 移行（PR #1408 マージ済み）
- [x] #1414 Ruby 4.0 移行
- [x] #1415 CI 改善（テスト本体の実行、Ruby 4.0 化）
- [x] #1410 CLI 新設と rake タスク整理（YAML 操作系は #1429 に分離、4.1.0 送り）
- [x] google-news-rss-cleaner 連携（cleaner URL 設定による切り替え実装済み）
- [x] #1430 ginseng-core `Config#errors` の検証対象を merged config に修正（ginseng-core v1.15.23 / #1431 クローズで完了）
- [x] #1416 監視（簡易 Web インターフェース + Kuma 連携）— Phase 1 (`/healthz`) + Phase 2 (`/healthz/source/:id`, `/status.json`, `source_run_log`) を develop に実装
- [x] #1407 GitHub Wiki の最新化と docs ↔ Wiki 整理 — CLI 新設・監視ページの追加、4.0 の廃止機能（ツイートタイムラインソース / マルチエントリ）と古い仕様の棚卸しを完了 (2026-04-14)
- [x] PR #1389 Codex レビュー対応 — `bin/shrieker source fetch` を summary 実装ソースに限定 (2026-04-14)
- [x] **v4.0.0.rc1 pre-release 公開** — develop `7674308` からタグ切り (2026-04-14)。ヘビーユーザー向けの事前テスト版
- [x] リリース前検証手順の docs 化 — `docs/release-validation.md` に test-*.yaml テンプレート + dry-run + Nostr スモークテスト + PieFed 実投稿テストを整備 (2026-04-19)
- [x] PiefedShrieker 常時 NameError 修正 (ee43038) — RC1 で PieFed 投稿が 100% 失敗していた (#4146 の include Package 削除時の取り残し) を `TomatoShrieker::Config.instance` 直参照で復旧 (2026-04-19)
- [x] **v4.0.0.rc2 pre-release 公開** — develop `064d57d` からタグ切り (2026-04-19)。RC1 の PieFed 修正版。RC1 で PieFed を試したテスターには RC2 で再確認依頼
- [x] Codex セキュリティレビュー（4周目で LGTM、2026-04-19）
- [x] Codex 指摘対応: 配信失敗の SourceRunLog 伝播 (20b4dd5)、Entry.create retry カウンタ修正 (46881dc)、exec 配下 rescue 撤去と overlap:false 付与 (2784d85)、Source#shriek に collect_delivery_errors フラグ追加 (9bc7a9f) (2026-04-19)
- [x] **v4.0.0 正式版リリース** — develop → master マージ (PR #1389)、v4.0.0 タグ + GitHub release (2026-04-19)
- [x] デフォルトブランチを `main` に変更 (2026-04-19)
- [ ] 本番デプロイ（別途相談）
- [ ] #1436 Google News 古記事再投稿の再検証（cleaner #6 デプロイ済、数日〜1週間様子見してクローズ）

### 4.1.0 以降

- [ ] #1429 CLI: ソース YAML 操作サブコマンド (add/edit/delete/validate)
- [ ] #1432 rake config:lint の CI 定常実行（local_sample.yaml 仕組み検討）
