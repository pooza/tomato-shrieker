# tomato-shrieker 開発ガイド

🔴🔴 **このファイルは自動ロードされるが、下の 4 本はされない。**⚠⚠ **「書いていない」と判断する前に、該当するファイルを開くこと。**

| 読むファイル | いつ読むか |
| --- | --- |
| [monitoring.md](monitoring.md) | 🔴 **`/healthz` / `/status.json` / `source_run_log` / `monitor:` 設定に触れるとき。**監視が赤い・緑すぎる話もここ |
| [sources.md](sources.md) | 🔴 **`config/sources/*.yaml` を読む・書くとき。**⚠ 実体は gitignore で **oscura にしかない** |
| [daemon.md](daemon.md) | 🔴 **daemon の起動・停止・`source reload` / `bin/shrieker` を叩くとき** |
| [sync.md](sync.md) | 🔴 **「進捗を同期してください」と言われたとき**（#1577 でスキル化予定） |
| [release-validation.md](release-validation.md) | 🔴 **リリース直前の手動検証** |

⚠ **迷ったら `grep -rn <語> docs/` で 5 本まとめて引く。**

## プロジェクト概要

投稿のソース・投稿先・スケジュールの3要素を組み合わせた、単純なつぶやきボットエンジン。
複数のボットを1インスタンスで管理できる。

- **技術スタック**: Ruby 4.0 / Rufus::Scheduler / SQLite3 (Sequel ORM)
- **投稿先**: Mastodon, Misskey, LINE, PieFed, Nostr, Webhook (Slack, Discord等)
- **ginseng-\*系gem**: 自作フレームワーク。必要に応じて全て更新してよい

## ブランチ戦略

⚠ **Issue 駆動・ブランチ命名（`fix/<issue>-<slug>`）・`gh pr create --base` の明示は [ginseng-style の workflow.md](https://github.com/pooza/ginseng-style/blob/main/docs/workflow.md) が正本。**ここに書き写さない。

| ブランチ | 目的 |
| --- | --- |
| `main` | リリース済み安定版（デフォルト）。**本番のデプロイ対象**＝ここへマージするのは必ずリリース |
| `develop` | 開発ブランチ。日常の作業はここで行う |

### リリースフロー

1. `develop` で開発・コミット
2. リリース時に `develop` → `main` へPRを作成しマージ
3. `main` でタグを打ちリリース: `gh release create vX.Y.Z --target main --title "X.Y.Z"`
4. `config/application.yaml` の `/shrieker/version` がバージョンの正本。リリース前に更新する
5. リリース直前に [release-validation.md](release-validation.md) の手順で各 Source / Shrieker の動作を手動検証する（CI では捕まらない統合系のリグレッション検出用）
6. 各マイルストーンの Issue をすべて消化した後、リリース直前に下記「リリース前レビュー」の 5 観点並列レビューを実施する。必修（赤）のみ本リリースで対応し、残り（黄・緑）は Issue 起票して次リリース以降へ送る
7. `docs/CLAUDE.md` のリリース済みセクションを更新する
8. **[Wiki](https://github.com/pooza/tomato-shrieker/wiki) を追従させる**（クローンは `~/repos/tomato-shrieker.wiki`・ブランチは `master`）。⚠ **Wiki は利用者向けの正本。**`docs/CLAUDE.md` は開発者向けなので、両方を更新しないと利用者から見た仕様が古いまま残る

⚠ **Wiki の更新漏れは溜まりやすい。**4.6.0 の時点で「監視」ページが **4.2.0 相当**のまま放置されており、4.4.0（配信計測・サイレント不発）と 4.5.0 の変更がまるごと欠落していた。**機能を追加・変更したリリースでは、対応するページを必ず開いて確認すること。**目安:

| 変更した領域 | 追従するページ |
|------|------|
| `/healthz` `/status.json` `source_run_log` 監視設定 | 監視 |
| `bin/shrieker` のサブコマンド | コマンドラインツール |
| マイグレーション・デプロイ順序・移行作業 | アップデート手順 |
| ソース種別・投稿先・スケジュール | 各ソース／Shrieker のページ |

### マイルストーンのサイズ

⚠ **正本は [ginseng-style の workflow.md](https://github.com/pooza/ginseng-style/blob/main/docs/workflow.md)。**ここには tomato での運用だけ書く。

- `size:S`（重み 1・50 行未満）/ `size:M`（3・50〜200 行）/ `size:L`（8・200 行超）を**全 Issue に付ける**。2026-08-21 に open 全件へ遡及付与した
- **1 マイルストーンの目安は 20〜25 重み。**超えたら Issue を次のマイナーへ送る
- ⚠ **大物（`size:L`）は 1 マイルストーンに 1 件まで**

重みの合計はこれで出せる。

```sh
gh issue list --state open --limit 60 --json number,milestone,labels \
  --jq '.[] | "\(.milestone.title // "未割当") \(.labels | map(.name) | map(select(startswith("size:"))) | join(""))"' \
  | awk '{w = $2=="size:S" ? 1 : $2=="size:M" ? 3 : $2=="size:L" ? 8 : 0; n[$1]++; c[$1]+=w} \
         END {for (k in c) printf "%s: %d 件 / 重み %d\n", k, n[k], c[k]}' | sort
```

### リリース前レビュー

各マイルストーンの Issue が消化済みになった後、バージョンバンプに入る前に実施する。**単一のセキュリティレビューだけでは実用上の問題が取りこぼされる**ため、以下 5 観点を独立したサブエージェントで並列に走らせ、指摘を合流させる（モロヘイヤ／capsicum で先行運用しているプラクティスの移植）。

| 観点 | 焦点 |
| --- | --- |
| セキュリティ | `/security-review` スキル。Webhook URL/トークン取り扱い・暗号化・Sentry/ログのシークレット scrub・フィード入力（RSS/nokogiri パース）の検証 |
| 設定・宛先契約 | ソース定義 YAML スキーマ整合（`config/schema/source.yaml`・`base.yaml`）・各 Shrieker の dest 解釈・ginseng-fediverse/piefed/youtube interface・本家 API（Mastodon/Misskey/Nostr/LINE/Matrix/PieFed）呼び出しの正確性・ソース定義リファレンスや `/healthz` 仕様との齟齬 |
| スケジューラ・ライフサイクル | rufus-scheduler の cron 駆動・`scheduler_daemon`・`source_run_log`・FeedItem 重複判定/entry 管理・Sequel 接続・CommandSource 子プロセス実行・seas(FreeBSD) daemon 駆動 |
| エラー処理・観測性 | Sentry 計装（source/shrieker タグ）・`Ginseng::GatewayError` の scrub・`/healthz` の error_streak / WARN/NG 判定・ログの本文/個人情報漏洩チェック |
| コーディングスタイル・規約整合性 | rubocop（+rubocop-sequel）・`rake config:lint`・設定のスラッシュ記法・2 スペースインデント・廃止語（lemmy 等） |

対象範囲は `v<前リリース>..develop` の差分。Codex（`chatgpt-codex-connector[bot]`）は PR ready 時に走るので併走させ、重複しない指摘だけを拾う。

⚠ **指摘の分類（赤＝必修 / 黄＝余力があれば / 緑＝送り）とその扱いは [workflow.md](https://github.com/pooza/ginseng-style/blob/main/docs/workflow.md) が正本。**必要最小限のみ本リリースで対応し、残りは Issue 起票して次リリース以降へ送る。

⚠ **上の 5 観点のうち共通なのは「セキュリティ」「エラー処理・観測性」「コーディングスタイル・規約整合性」の 3 つ**で、正本にも同じものがある。**「設定・宛先契約」「スケジューラ・ライフサイクル」が tomato 固有**の観点。

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

**緊急性の判断**: SA の severity 表記 (high 等) は CVSS ベースの汎用評価であり、tomato-shrieker での実発火可能性とは別レイヤで評価する。外部入力を扱う gem（フィード解析の nokogiri 等）は警戒、未使用 gem（net-imap 等）や信頼できない入力経路の無い gem（erb 等）は実害が薄い。実発火経路が薄ければ単独ホットフィックスを切らず、次の通常リリースに Gemfile.lock 更新として含めれば十分。

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
| NostrShrieker | (独自実装) | Nostr イベント ⚠ **動作保証対象外** |
| WebhookShrieker | SlackService | Webhook (Slack, Discord等) |

⚠ **NostrShrieker は動作保証の対象外。**運用者が使っておらず、実運用での検証経路が無いため。リリース前検証（[release-validation.md](release-validation.md)）にも含めない。

**ただし打ち切りではなく「報告があったら対応する」ステータス。**こちらから能動的に検証したり先回りして直したりはしない、という意味であって、報告された不具合を放置するわけではない。対応のトリガーは **issue での報告**と **Codex レビューの指摘**の 2 つ。

実例: 4.4.0 で Codex が「全リレー失敗でも配信成功として計上される」を P1 で指摘 → 本番の nostr 宛先は 0 件だったが、この方針に沿って `4a20bf5` で修正した。

## 重要な設計判断

### CommandSource の子プロセス実行

`Bundler.with_unbundled_env` で囲む（親の RUBYOPT, GEM_HOME 等の漏洩防止）。
ただし `command.env['BUNDLE_GEMFILE']` は引き続き必要（with_unbundled_env で一掃された後、子プロセスに正しい Gemfile 位置を教える役割）。

⚠ **`with_unbundled_env` は `RBENV_VERSION` と `PATH` は消さない。**したがって子プロセスは**本体と同じ Ruby で動き、サテライト側の `.ruby-version` は無視される**。サテライトの gem は本体と同じバージョンの gem ディレクトリに入っている必要がある（[daemon.md の デプロイ手順](daemon.md#デプロイ手順) 参照）。

⚠ **`register` の自動 `bundle_install` は `bundler?`（コマンドが `bundle` または `bundler` で始まる）が真のときだけ走る。**`bin/loquat.rb` のように直接実行する定義では走らないので、サテライトの `bundle install` はデプロイ手順の側で担保する。

🔴 **動作確認のつもりで設定どおりのコマンドを手で叩いてはいけない。**サテライト側が「通知済み」状態を持っていることがあり、実行しただけで**次の定期実行ぶんを食い潰す**。実例: `loquat reserves` は `-n`（保存しない）を付けないと `tmp/cache/reserves-*.json` を更新するので、`precure-reserve`（`-n` なし）を手動実行すると未告知の予約が投稿されないまま消える（2026-08-04 に発生。キャッシュを消して再告知した）。⚠ **`dqdai-reserve` には `-n` が付いており、同じ `loquat reserves` でも挙動が違う。**復旧確認は各ソースの定義を読んでから、副作用のない形（`-n` 相当があるか / 冪等か）を確かめて行う。

### ginseng-\* gem のデフォルトブランチ

全て `main` に統一済み。Gemfile で `branch: 'main'` を明示指定する。

## 設定構造

- `config/application.yaml` — デフォルト設定
- `config/local.yaml` — ローカル上書き（git 管理外）
- `config/sources/*.yaml` — ソース定義（動的読み込み）
- `config/schema/base.yaml` — JSON Schema によるバリデーション

設定アクセスは Ginseng のスラッシュ記法: `config['/path/to/key']`

### Schema 設計の指針 (required の意味論)

ginseng-core v1.15.23 (#477) 以降、`Config#errors` は merged config (application.yaml + local.yaml) を検証する。これに伴い required の意味は **「merged 後の最終 config に必ず存在すべきキー」** に統一されている。

「local.yaml で必ず上書きすべき値 (= 既定値のままでは本番投入させない)」を schema で守りたいときは、custom validator を作らずに以下の組み合わせで実現する:

1. `application.yaml` で該当キーを `null` にする
2. `schema` で該当キーを `required` + 必要なら `type: string` / `minLength` 等を指定
3. `Hash.deep_merge` の `compact` が null をドロップするので、local.yaml で上書きされない限り merged config に該当キーが存在せず、required 違反になる

逆に **既定値が application.yaml に埋まるキーを top-level required に置いても無意味** (常に通る)。実例: `crypt.password` は application.yaml で `null`、schema で `crypt.required: [password]`。

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

⚠ **正本は [pooza/ginseng-style](https://github.com/pooza/ginseng-style)。** ここに書き写さないこと。

| ドキュメント | 内容 |
| --- | --- |
| [docs/ruby.md](https://github.com/pooza/ginseng-style/blob/main/docs/ruby.md) | Ruby の書き方（暗黙の return を使わない、テストの `disable?` パターン、文字列のエンコーディング） |
| [docs/workflow.md](https://github.com/pooza/ginseng-style/blob/main/docs/workflow.md) | Issue 駆動・ブランチ・サイズラベル・リリース前レビュー・`ginseng-*` の変更手順 |
| [docs/writing.md](https://github.com/pooza/ginseng-style/blob/main/docs/writing.md) | 表記規約（用語・パスとキーの書き方・⚠ マーカーの使い方） |
| [docs/rationale.md](https://github.com/pooza/ginseng-style/blob/main/docs/rationale.md) | なぜ正本化したか |

RuboCop の設定も同じ gem が持つ（`.rubocop.yml` は `inherit_gem` で差分だけ）。⚠ **共通に見える緩和をこちら側に足さないこと。** 共通化したい場合は ginseng-style に Issue を立てる。

トマトすぐ死ぬ固有:

- テスト: test-unit (`TomatoShrieker::TestCase` 基底クラス)
- `.rubocop.yml` に残している差分は `TargetRubyVersion` と `rubocop-sequel`（`Sequel/*`）だけ

### 例外メッセージは `Package.error_message` を通す

🔴 **例外メッセージを保存・レスポンス・ログに載せるときは、直接埋め込まず `Package.error_message(error)` を通す**（#1469）。

⚠ **Sequel / SQLite の例外メッセージは ASCII-8BIT で上がる。**日本語を含む SQL が失敗すると `"#{error.class}: #{error.message}"` は非 ASCII バイトを持つ ASCII-8BIT 文字列になる。

| 中身 | json 2.x | json 3.0 | UTF-8 文字列との `<<` |
|------|----------|----------|----------------------|
| 妥当な UTF-8 バイト | 警告のみ（通る） | **例外** | **`Encoding::CompatibilityError`** |
| 不正バイト | **`JSON::GeneratorError`** | 例外 | 同上 |

⚠ **ASCII-8BIT では `valid_encoding?` が常に true** なので、検査で分岐しても意味がない。`Package.error_message` は `String#to_utf8`（`force_encoding` してから `scrub`）で無条件に倒す。

🔴 **この経路が通るのは異常時だけなので、壊れていても平常時には気付けない。**とくに `rescue` 節の中で例外メッセージを組み立てるところは、**エラーを報告しようとして同じ例外を踏む**構造になりやすい。`rescue` の中でも必ず通す。

⚠ **保存側だけでは足りない。**正規化を入れる前に書かれた行が DB に残るので、`SourceRunLog#error_message` は読み出し側でも正規化する。

## 運用ルール

### Sentry コメント運用

Sentry イシューをクローズせず経過観察とする場合、その意図を Sentry イシューのコメントに記録する。「経過観察」「再発待ち」「次バージョンで対応予定」など、クローズしない理由を明記し、単なる放置と区別できるようにする。

### 投稿先ごとのテスト厚みの非対称

🔴 **運用者は Webhook（モロヘイヤ経由）しか使っていないが、Mastodon / Misskey の API へ直接投稿している外部ユーザーがいる。**その結果、**利用者がいる経路のテストがいちばん薄い**という逆転が起きている。

本番 40 ソースの内訳（2026-08-06 実測）:

| Shrieker | 本番での使用 | 外部ユーザー |
|----------|--------------|--------------|
| WebhookShrieker（モロヘイヤ経由） | **40 件すべて** | — |
| MastodonShrieker（直接） | **0 件** | 🔴 **いる** |
| MisskeyShrieker（直接） | **0 件** | 🔴 **いる** |
| LineShrieker | 2 件 | — |
| PiefedShrieker | 0 件 | 不明 |
| NostrShrieker | 0 件 | 別枠（下記） |

⚠ **運用者の目線だけで優先度を決めると、直接経路が永久に検証されないまま残る。**Mastodon / Misskey に触れる変更は、本番で 0 件だからといって影響が小さいと判断しない。検証環境の整備は #1481。

⚠ **Nostr をこの非対称と同列に扱わない。**Nostr にも外部ユーザーはいるが、下記のとおりテスト責任の所在が違う。

### Nostr のテスト責任

Nostr 対応は外部ユーザーのリクエストで実装された機能。動作確認・テストの責任はリクエスト元ユーザーが負う（伝達済み）。不具合があれば対応するが、積極的なテストは行わない。

⚠ **Mastodon / Misskey の直接経路との違いは「テスト責任を引き受けたかどうか」。**直接経路は tomato-shrieker が責任を持つ中核機能で、薄いテストは埋めるべき欠落。Nostr はリクエスト元が責任を負う合意があるので、報告ベースの受動対応でよい。

## 過去のリリース計画

- 4.0 の計画・設計メモは [archive/v4-plan.md](archive/v4-plan.md) に保存（2026-04-19 に v4.0.0 リリース完了）
- 4.1.0 以降の進捗は GitHub の Issue / Milestone で管理する

## 情報の記載先ルール

⚠ **「課題・タスクは Issue で管理する」「docs に書くだけでは管理されていない扱い」は [workflow.md](https://github.com/pooza/ginseng-style/blob/main/docs/workflow.md) が正本。**tomato 固有はこの 2 つ。

- **プロジェクト共有すべき知見** → `docs/` 配下の git 管理下のファイルに記載する。⚠ **メモリにだけ置かない**
- 🔴 **書く先を間違えない。**`CLAUDE.md` は**毎回読む必要があるもの**だけに絞る（自動ロードされる唯一のファイルなので、太らせると毎回のコストになる）。領域ごとの詳細は [monitoring.md](monitoring.md) / [sources.md](sources.md) / [daemon.md](daemon.md) / [sync.md](sync.md) へ。⚠ **どちらか迷うなら「この話を知らずに作業を始めると事故るか」で決める**
- **進捗の同期** → `MEMORY.md` だけでなく `docs/` 側も更新すること。特にリリース済みバージョンの反映（「開発中」→「リリース済み」への変更）を忘れないこと

## 関連リポジトリ

- [ginseng-core](https://github.com/pooza/ginseng-core) — 基盤ライブラリ（branch: main）
- [ginseng-fediverse](https://github.com/pooza/ginseng-fediverse) — Fediverse 対応
- [ginseng-youtube](https://github.com/pooza/ginseng-youtube) — YouTube 対応
- [mulukhiya-toot-proxy](https://github.com/pooza/mulukhiya-toot-proxy) — 姉妹プロジェクト（構成が類似）
- [google-news-rss-cleaner](https://github.com/pooza/google-news-rss-cleaner) — Google News redirect URL 解決ツール（kues 上で systemd 稼働、Node.js + Playwright）。tomato-shrieker の管理対象に含む
- [chubo2](https://github.com/pooza/chubo2) — itamae ベースの構成管理。インフラ課題の issue 管理先
