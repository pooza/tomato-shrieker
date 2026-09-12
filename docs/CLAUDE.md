# tomato-shrieker 開発ガイド

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
      → SchedulerDaemon#migrate (未適用ならマイグレーション)
      → MonitorServer#start (Puma embedded / 監視用 HTTP)
      → SchedulerDaemon#start_reload_worker (SIGHUP → Queue → Scheduler#reload)
      → Scheduler.instance.exec (Rufus::Scheduler)
        → Source.all → register (各ソースをスケジューラに登録)
```

systemd/rc.d からは bin スクリプトを直接呼ぶ。`rake start` / `rake restart` は廃止済み（#1410）。

### 起動時マイグレーション

**未適用のマイグレーションは起動時に自動適用される。**デプロイ手順に `rake migrate` を書き忘れても、スキーマが古いまま走ることはない。適用済みなら何もしない（`Sequel::Migrator.is_current?` で判定）。失敗した場合は起動させずに落とす — 古いスキーマのまま動くと、実行時に分かりにくい形で壊れるため。

⚠ もともと `rake start` / `rake restart` の前提タスク（`migration:run`）として走っていたが、#1410 で rake タスクを廃止したときに一緒に落ちて手動になっていた。`rake migrate` は手動実行用に残してある。

### ソース定義の reload (#1459)

**稼働中の scheduler にソース定義を読み直させる。**`bin/shrieker source add / edit / delete / disable / enable` はファイルを書くだけなので、以前は反映に再起動が要った。

```sh
bin/shrieker source disable foo
# disabled: foo
# ⚠ 稼働中の scheduler に反映するには bin/shrieker source reload

bin/shrieker source reload
# reload requested (pid 1322485)
```

`source reload` は `tmp/pids/SchedulerDaemon.pid` を読んで **SIGHUP** を送る。daemon 側は trap で Queue に積み、専用スレッドが `Scheduler#reload` を呼ぶ。⚠ **trap 文脈では Mutex を取れない**（`ThreadError`）ので、trap で直接 reload してはいけない。

🔴 **trap は pid が外から見えるより前に張る。**`Ginseng::Daemon#run_start` は `start` を呼ぶ**前に** pid を書くので、`source reload` は**書かれた瞬間から**「生きている」と見て HUP を送れる。⚠ **trap が無い間に届くと、既定動作で daemon が死ぬ。**⚠⚠ **`start` の先頭で張るのでは閉じない**（実測: `write_pid` から `start` の trap までは med 0.013ms / max 2.26ms・n=200。CLI 側は pid ファイルを読んだ直後に撃つので、窓が縮むだけで原理的に残る）。そこで **`write_pid` を override** して、`super` の前に trap を張る。⚠ **`run_start` は override しない** — `abort_if_running!` / TERM・INT の trap まで複製することになり、上流が [#509](https://github.com/pooza/ginseng-core/issues/509) / [#510](https://github.com/pooza/ginseng-core/issues/510) / [#532](https://github.com/pooza/ginseng-core/issues/532) で個別に塞いだレースを写し取る羽目になる。⚠ **ただし処理は起動完了後。**マイグレーション前にジョブを立てると `no such table` を踏むので、監視サーバーを上げるまでは**積むだけ**にする。

🔴 **reload するのは「ソース定義」だけ。**`Ginseng::Config#load` は `next if @raw.key?(key)` で一度読んだファイルを二度と読まないため、`application.yaml` / `local.yaml` は反映されない。⚠ **「reload ＝ 設定を全部読み直す」と説明すると嘘になる。**`/monitor/bind` のようなキーを稼働中に差し替えられても困るので、これは**仕様として維持する**（コマンド名が `source reload` なのはそのため）。

**差分だけをジョブに反映する。**id 単位で設定の digest を持ち、**無変更のソースはジョブに触らない**。⚠ **起動時の初回登録も同じ差分適用を通す。**SIGHUP は起動の途中から受け付けるので、初回登録と reload が両方とも素通しで `register` すると**同じソースにジョブが 2 本立ち、以後は digest が一致するので誰も気付けない**（＝ 1 周期に 2 回投稿する）。

- ⚠ **全件を貼り替えてはいけない。**`every` は登録時に発火しない代わりに、差し替えると**次回発火が 1 周期先へずれる**。全件貼り替えは全ソースの位相をリセットする
- ⚠ **消すのは job id ではなく tag。**`IcalendarSource#register` は remind と本体の 2 本を**同じ `tag: id`** で登録し、`register` の戻り値は本体ぶんだけ。job id を控える設計にすると remind ジョブが取り残される
- ⚠ `schedule_maintenance`（prune）の日次ジョブは**無タグ**。「全部 unschedule」をやると巻き添えで消える
- ⚠ **実行中の run は殺さない。**`unschedule` は以後の発火を止めるだけなので、**進行中の run は古い定義のまま完走する**
- 🔴 **起動は fail closed、reload は fail safe。**起動時に 1 件でも `register` に失敗したら**起動しない**（`Ginseng::ConfigError`）。⚠ ここで飛ばすと**そのソースは二度と登録されないのに daemon は正常に見える**（総合 `/healthz` は無タグの maintenance ジョブがあれば通る）。倒しておけば systemd の `Restart=always` が 5 秒後に再試行する。⚠ **一方 reload では倒さない。**稼働中の daemon を「誰かが YAML を打ち間違えた」で落とす理由は無い
- 🔴 **新しいジョブを立ててから古いジョブを落とす。**`register` は失敗しうる（`CommandSource` は `bundle install` を走らせるし、reload はスキーマ検証をしないので**不正な cron 式**もここへ来る）。先に消すと、**失敗したソースが次の reload までジョブ 1 本無いまま放置される**。⚠ **失敗した id は registry を更新しない**ので、定義を直せば次の reload で必ず張り直る。⚠ 1 ソースの失敗は他のソースの反映を止めない（ログの `failed` に出る）
- 🔴 **壊れた定義を掴んだら何も変えない。**`Config#load` は読み切ってから 1 回で差し替える（#1530）ので、YAML が 1 つでも壊れていれば例外だけが上がり、**ジョブも設定も前のまま**走り続ける
- ⚠ **reload ではスキーマ検証をしない。**起動時が検証していないのに reload だけ厳しいと「起動はできるのに reload は拒否される」定義が生まれる。検証は `source edit` / `source validate` の担当

⚠ **自動 reload はしない。**`add` / `edit` の契約を 1 つずつのままに保つため（`source add` は $EDITOR を開く**前に**スキーマ妥当な雛形を書くので、ファイル監視だと `example.com` へ投げるジョブが即座に立つ）。⚠ **監視エンドポイントに `POST /reload` も置かない。**読み取り専用だった監視面が制御面になる。

⚠ **シグナルは非同期なので、CLI は「要求した」までしか言えない。**結果はログの `{"scheduler":"reload","added":[...],"removed":[...],"changed":[...],"failed":[...]}` 行で見る（起動時の初回登録は `"scheduler":"register"`）（同期で受け取る手段は #1529）。daemon が停止中なら「次回起動時に読み込まれます」と言って正常終了し、`:unknown`（EPERM ＝ pid のプロセスに触れない）はエラーにする。⚠ **`:unknown` を `:dead` と混ぜない。**

### デプロイ手順

本番は oscura（Ubuntu / systemd）、実行ユーザー `deploy`、チェックアウトは `/home/deploy/repos/tomato-shrieker`。デプロイ対象は **`main` ブランチ**（develop は本番へデプロイしない）。

```sh
# 本体
ssh oscura 'sudo -H -u deploy bash -lc "cd ~/repos/tomato-shrieker && git pull origin main && bundle install"'

# サテライト 3 本（CommandSource の実行対象。それぞれ独立した Gemfile を持つ）
ssh oscura 'sudo -H -u deploy bash -lc "
  RV=\$(cat ~/repos/tomato-shrieker/.ruby-version)
  for d in loquat:main shooby-do-bop:master dqdai-anniv:main; do
    cd ~/repos/\${d%%:*} && git pull origin \${d##*:} && RBENV_VERSION=\$RV bundle install
  done"'

ssh oscura 'sudo systemctl restart tomato-shrieker'
```

🔴 **`bundle install` は本体・サテライトとも毎回必ず実行する。**冪等なので無駄打ちのコストはほぼ無い。省くと以下で壊れる。

- **Ruby のマイナー更新**（例: 4.0.5 → 4.0.6）で gem ディレクトリが総入れ替えになる。本体だけ `bundle install` してサテライトを忘れると、**サテライトだけが `Bundler::GemNotFound` で全滅**する（2026-08-03 に実際に発生。`loquat` / `shooby-do-bop` / `dqdai-anniv` の 7 ソースが `timecop` 欠落で 24 時間エラー）
- ginseng-\* gem は `branch: main` 追いなので、`Gemfile.lock` が同じでも中身が動く

⚠ **サテライトの `.ruby-version` は当てにならない。**scheduler_daemon の環境には `RBENV_VERSION` が入っており、それが子プロセスへそのまま継承される。つまりサテライトは自分の `.ruby-version` ではなく **本体と同じ Ruby で動く**（[CommandSource の子プロセス実行](#commandsource-の子プロセス実行) 参照）。`bundle install` も同じバージョンを明示して実行すること。

⚠ `git pull` を引数なしで打つと `There is no tracking information for the current branch.` で止まる。itamae の `git` リソースが upstream 追跡を持たないローカルブランチ `deploy` に着地させるため。本体は必ず **`git pull origin main`** と書く（ブランチ名が実行ユーザー名と同じなのは偶然）。

⚠ `shooby-do-bop` の既定ブランチは `master`（他は `main`）。

⚠ `config/local.yaml` と `config/sources/` は gitignore 配下＝git では上がってこない。ソース定義の正本は本番の実体で、手元の `config/sources` は dev 用。

⚠ `rake migrate` は不要（起動時に自動適用される。上記「起動時マイグレーション」参照）。

⚠ **順序は「pull → 再起動 → CLI」で固定する。**マイグレーションを走らせるのは `SchedulerDaemon#start` だけで、`bin/shrieker` は `Sequel.connect` しかしない。再起動前に新テーブルを触るサブコマンド（`source ack` → `silence_ack`）を叩くと、Thor のエラーではなく生の `Sequel::DatabaseError: no such table` で落ちる。

### 本番操作の注意

- ⚠ **本番のチェックアウトを `git` で覗くときは必ず `deploy` ユーザーで。**`ssh oscura 'git -C ~deploy/repos/tomato-shrieker log'` は `detected dubious ownership` で落ちる。`sudo -iu deploy bash -lc "cd ~/repos/tomato-shrieker && git log"` と書く（`sudo -u deploy` では rbenv が効かず system ruby になるので `-i` が要る）
- 本番デーモンは必ず OS のサービス管理経由 (`systemctl restart tomato-shrieker` / `service tomato_shrieker restart` 等) で操作する。SSH ワンライナーで `scheduler_daemon.rb start` を直接呼ぶとセッション切断時にプロセスが死ぬ（v3.9.10 インシデントの教訓）
- Monit を停止/再開する際は事前にユーザーに確認する

### seas (FreeBSD) 固有

- v4.0 の sample rc.d (`config/sample/freebsd/tomato_shrieker`) は `bash -lc` でデーモンを起動する。pooza の rbenv init は `.zshenv` にしかなく bash login shell では拾えないため、`~/.bash_profile` に `eval "$(rbenv init - bash)"` を追加してある。この dotfile が消えると rc.d が system ruby を掴んで `Bundler::RubyVersionMismatch` になる
- 監視エンドポイントの `/monitor/bind` は Tailscale IP `100.99.186.51` 固定で loopback 以外に漏らさない。ipfw は `tailscale0 interface 全許可` ルール (60020) を `/usr/local/etc/ipfw.rules` に永続化済。Kuma からは MagicDNS で `http://seas.tailf29562.ts.net:4567/healthz` を叩く

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

該当ソースが以下をすべて満たせば 200:

- 配信先が 1 つ以上ある (`dest_count > 0`)
- 最終実行から `grace_seconds` 以内に走っている (stale でない)
- 連続エラー回数が `error_streak_threshold` 未満である（ソース単位で上書き可・#1558）
- **直近の配信試行に取りこぼしが無い (undelivered でない)**
- `silence_tolerance` を超えて無配信が続いていない (silent でない)

**宛先の一部にだけ配信できていない状態を検知する (#1504)。**直近の「配信を試みた run」(`attempted_count > 0`) で `delivered_count < attempted_count` なら 503。

🔴 **2026-06 の Matrix 配信停止 (#1455) がこの形だった。**matrix 系 3 ソースは `hooks` を 2 つ持ち、`hook[0]`（matrix-webhook）が毎回失敗する一方 `hook[1]`（モロヘイヤ）は成功していた。`delivered_count > 0` なので status は `partial`、`last_delivered_at` も前進し続け、**error_streak も silent も立たず監視は最後まで緑だった。**

⚠ **解除は「次に全宛先へ届いた run」だけ。no-op run では解除しない。**取りこぼしたエントリは再送されない（`Entry.insert` が配信より先に走り、`entry.tooted` 列は `migration/004` で削除済み）ため**永久に失われている**。新着が無いことは失敗の解消にならない。

🔴 **だからこそ `attempted_count` に載せてよいのは「宛先に触れた試行」だけ。**解除条件が「次に配信できるまで」である以上、過検知の代償は「翌日まで赤」ではなく**「次に新着が出るまで赤」**になる。本番の実測では 12 日間に 1 度も配信を試みていないソースが 40 件中 13 件あり、疎なソースなら数週間に及ぶ。

- **宛先を組み立てられなかった**（アクセサが例外を握って nil を返した）→ `DeliveryStats#record_unavailable` で **attempted に載せる**。届いていないのは事実なので未達で正しい
- **配信より手前で落ちた**（`Entry.create` の `SQLite3::BusyException`、`create_template` の失敗等）→ `DeliveryStats#record_failure` で **attempted には載せない**。宛先は全部健全なのに「宛先に届いていない」と表示すると、運用者は存在しない宛先障害を探しに行く。`@errors` には積むので status は `error` / `partial` に倒れ、`error_streak` では捕まる

⚠ **宛先ごとの識別子は持たない。**Kuma のモニターがソース単位なのでアラートの粒度は元からソース単位であり、1 ソースに宛先を詰め込んで粒度が落ちるのは運用側の判断とする。また hook の URL にはトークンが入っており、宛先を記録すると run_log と `/status.json` にシークレットが載る。**503 の本文には `attempted_count` / `delivered_count` だけを出し、どの宛先かは設定を見て切り分ける。**

⚠ **`delivered_count == 0`（全滅）も同じ式で拾える**ので `error_streak` と二重管理にならない。

⚠ **判定の根拠行は prune から守る**（`last_attempted_ids`）。刈ると赤くなったソースが `retention_days` の経過だけで黙って緑に戻る。

📌 **`silent` との違い。**「試したのに届かなかった」は無条件に失敗だが、**「長期間配信が無い」は一概に失敗と言えない**（上流が静かなだけの場合がある）。前者は常時有効、後者は opt-in。

ソースが存在しない場合は 404。`/schedule/at` の単発ソースは監視対象外として常に 200 を返す。

🔴 **`disable: true` のソースも監視対象外で、常に `OK (disabled)` の 200 (#1503)。**scheduler は `reject(&:disable?)` で無効ソースを register しないので `executed_at` が二度と前に進まない。**一度稼働してから無効化すると `stale` が恒久的に成立し、Kuma のモニターが永久に赤くなる**（無効化直後は 200 なのでその場では気付けない）。⚠ **「意図的に止めた」と「壊れている」を同じ 503 で表さない。**`/status.json` が `reject(&:disable?)` しているのと同じ規則で揃えてある。

**宛先ゼロは実行結果を見るまでもなく壊れている (#1473)。**`No destination configured` を返して 503 に倒す。`dest: {}` や `dest: {hooks: []}`、`token` を落とした `dest.mastodon` のような半端な設定は `shriekers` が 1 件も yield しないため配信が永久に起きないが、run は no-op success を積むだけで健全に見える。

🔴 **設定は正しいのに Shrieker を組み立てられない場合も同じ穴になる (#1504)。**各アクセサ（`mastodon` / `misskey` / `line` / `piefed` / `nostr`）は生成時の例外を `rescue` して nil を返すので、**PieFed が落ちている・上流が 429 を返す・URL のスキームが欠けている**といった理由でその宛先が `shriekers` から黙って消える。`dest_count` は設定を数えるだけなので気付けない。`Source#shriek` が `dest_count` と yield 数の差を `record_unavailable` で計上し、未達として倒す。⚠ **この差分を計上しないと `dest_count` は「表示するだけの数字」になる。**

⚠ **ただし `disable: true` のソースは除く (#1486)。**スキーマが無効ソースに対して `dest` の配信先必須を免除している（`chinachu` 等の死蔵定義が実際に `dest: {}`）ので、ランタイムだけ咎めると宣言と食い違う。**#1503 以降、無効ソースは宛先チェックの手前で 200 に抜ける**ので、この食い違いは監視の入口で片付いている。

**エラー判定は連続エラー回数 (error_streak) で行う (#1457)。**streak はエラーで終わった run を新しい順に数え、**エラーでない run が来た時点で 0 に戻る**。新着が無く配信ゼロで完走した run (no-op) も「run が最後まで走った」証拠なので streak を切る。

⚠ **no-op を読み飛ばす実装にしてはいけない。**新着の少ないソースは配信が起きるまで no-op が続くため、一過性エラー 1 回で `/healthz/source/:id` が次の配信まで 503 に貼り付く。何回の連続エラーで倒すかは `/monitor/error_streak_threshold` で調整する。

**サイレント不発の判定 (#1470)** は `silence_tolerance` を宣言したソースだけが対象（opt-in）。`chikanan` のように年単位で正常に静かなソースがあるため、一律の既定値は置かない。

**沈黙を測る起点は「配信・確認・観測開始のうち最も新しいもの」(#1505)。**

```
silent? = now > max(last_delivered_at, silence_acknowledged_at, observed_since) + silence_tolerance
          ただし配信実績も確認記録も無く、まだ超えていなければ nil (= 判定不能・#1502)
```

⚠ **「長期間配信が無い」は一概に失敗と言えない。**上流が静かなだけのこともある（実例: `precure-toei-event` は東映のイベントが実際に開催されていなかった）。とはいえ**何らかのエラーを抱えている疑いがある状態**でもあるので、**いったん赤にして、静かなだけと分かったら運用者が確認して緑に戻す**。

```
bin/shrieker source ack ID
```

🔴 **確認は「今回は問題なかった」の記録であって「今後も問題ない」の保証ではない。**起点が前に進むだけなので、**そこからさらに `silence_tolerance` が経過すれば再び赤になる**（「また 1 か月経ったけど、やっぱりおかしくない?」という念押し）。配信が再開すれば `last_delivered_at` が確認を追い越すので、確認記録は自然に無効化される。

🔴 **`ack` は未達 (`undelivered`) にも効く (#1506)。**⚠ **消えるのは「確認したその試行」だけ**で、確認より後の試行で再び届かなければまた赤くなる（サイレント不発と同じ規則）。

⚠⚠ **「確定的な信号を運用者が消してよいのか」は判断した上でこうしている。**取りこぼしたエントリは**再送されないので、赤を放置しても失われたものは戻らない**。一方 **2026-09-05 の実測では 57 ソースのうち 17 件が 12 日間に配信試行ゼロ**で、逃げ道が無いと疎なソースは数週間 503 に貼り付く。**「いつも赤いモニター」は監視ごと信用されなくなる**ほうが害が大きい。

⚠ **`ack` はソースごとに 1 つの記録**（`silence_ack` テーブル）なので、**サイレント不発と未達のどちらを確認しても両方に効く**。`bin/shrieker source ack` は**実際に効いた範囲だけを出力する**。

📌 **この仕組みがあるので `silence_tolerance` を保守的に丸める必要は無い。**偽陽性のコストが「設定を直す」から「1 回確認する」に下がる。

⚠ **確認済みのソースは `silent: false` になるが、それは健全だからではない。**`/status.json` の `silence_acknowledged_at` で「なぜ緑なのか」を答えられるようにしてある。

ソースの状況ごとの使い分け:

| 状況 | 対処 |
|------|------|
| 一時的に静か（たまたま 1 か月新着が無かった） | `bin/shrieker source ack ID` |
| 投稿が恒久的に終了した | `bin/shrieker source disable ID`（＋ `source reload`） |
| 年単位で正常に静か（`chikanan` 等） | `silence_tolerance` を設定しない |

⚠ **`disable` にしたソースは監視対象外になり、`/healthz/source/:id` は `OK (disabled)` の 200 を返す (#1503)。**「意図的に止めた」と「壊れている」を同じ 503 で表さない。

⚠ **判定に使うのは run_log 由来の実配信だけで、`fallback` は見ない (#1483)。**下記のとおり `fallback` は配信の成否と無関係に前進するため、これを信じると配信できていなくても `silent?` が永久に false になる。

**一度も配信していないソースは、観測を始めてからの経過 (`SourceRunLog.observed_since`) を無配信期間の下限として使う (#1483)。**ここを「配信実績が無いので断定しない」で健全側に倒すと、**開設以来ずっと壊れているソースだけが恒久的に検知対象外になる**という逆立ちした挙動になる。

🔴 **`silent` は 3 値 (#1502)。**`true` = 沈黙、`false` = 沈黙していない、**`null` = まだ判定できない**。

⚠⚠ **`false` が「健全」と「判定不能」を兼ねていた。**上の下限に頼っている以上、**run_log 上に配信実績が無いソースは「観測開始から `silence_tolerance` 経過するまで」検知されない**。2026-09-05 の本番実測で該当するのは **2 件**で、`precure-toei-event`（180d・観測開始 2026-08-03）は検知が **2027-01-30 まで**、`precure-toei-news`（90d）は **2026-11-01 まで**後ろ倒しになる。⚠ **検知しないこと自体は #1483 の判断どおりで変えない。嘘をつかないようにしただけ。**

**なぜその判定なのかは `silence_baseline_origin` で読む。**

| 値 | 意味 |
|---|---|
| `delivery` | run_log 上の実配信が起点。判定は確か |
| `acknowledgement` | 運用者の確認が起点 (#1505)。緑なのは健全だからではない |
| `observation` | **観測開始が起点。配信実績も確認記録も無い**＝ `silent` は `null` か、下限だけを根拠にした `true` |

⚠ **初回 run でいきなり配信できたソースは `observed_since` と時刻が一致する**が、`delivery` が勝つ（同着は宣言順）。

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
      "grace_seconds": 600,
      "last_run_at": "2026-04-14T14:00:00+09:00",
      "next_run_at": "2026-04-14T14:05:00+09:00",
      "last_status": "success",
      "last_error": null,
      "last_duration_ms": 423,
      "dest_count": 1,
      "last_attempted_count": 2,
      "last_delivered_count": 2,
      "last_attempted_at": "2026-04-14T14:00:01+09:00",
      "undelivered": false,
      "last_delivered_at": "2026-04-14T14:00:01+09:00",
      "last_delivered_at_origin": "run_log",
      "error_streak": 0,
      "error_streak_threshold": 1,
      "noop_streak": 0,
      "silence_tolerance_seconds": null,
      "silent": false,
      "silence_baseline": "2026-04-14T14:00:01+09:00",
      "silence_baseline_origin": "delivery",
      "silence_acknowledged_at": null,
      "error_rate_24h": 0.0,
      "duration_ms": {"min": 120, "avg": 380, "max": 1200, "p95": 900},
      "shrieker_errors": {"MastodonShrieker": 1}
    }
  ]
}
```

Kuma からは見ない（人間が `curl | jq` する用、または外部ダッシュボードに食わせる用）。

`last_delivered_at_origin` は配信時刻の出どころ:

| 値 | 意味 |
|------|------|
| `run_log` | 保持期間内の実配信記録 |
| `fallback` | ソース種別ごとの永続データ由来。`FeedSource` 系は `entry` テーブルの最新 `published` |
| `null` | どちらからも取れない（＝配信実績を確認できない） |

⚠ **`fallback` は人間が読むための参考値で、`silent?` は使わない (#1483)。**`entry.published` は上流フィードが自称する公開時刻で、`Entry` の行は配信の成否と無関係に INSERT される。**配信できていなくても上流に新着があるかぎり前進し続ける**ので、判定に使うと「配信していないのに健全」になる（Google News の pubDate が信用できない件と同根）。一次情報は `run_log` 側。

⚠ **prune はソースごとに 3 行を守る。**

| 守る行 | 理由 |
|------|------|
| 最後に配信できた run | 刈ると沈黙が `retention_days` を超えた瞬間に `last_delivered_at` が nil に化け、**沈黙が長引くほど検知できなくなる** (#1470) |
| 最古の run | 未配信のソースは上の保護に引っかからない。刈ると `observed_since` が常に `retention_days` 前に張り付き、それより長い `silence_tolerance` が永久に成立しない (#1483) |
| 最後に配信を試みた run | 刈ると未達で赤くなったソースが `retention_days` の経過だけで黙って緑に戻る。**次に配信できたときだけ解除する**という仕様が壊れる (#1504) |

`silence_tolerance` に `retention_days` より大きい値を書けるのはこの保護があるため。

**腐った設定と「正常に静か」の見分け方**は `silent` と `last_delivered_at` を突き合わせる。`last_status` は「run が完走した」を意味するだけで「配信した」ではないので、これだけを見てはいけない。

### 設定

| キー | 既定値 | 意味 |
|------|--------|------|
| `/monitor/enabled` | `true` | `false` で監視サーバの起動をスキップ |
| `/monitor/bind` | `127.0.0.1` | バインドアドレス |
| `/monitor/port` | `4567` | リッスンポート |
| `/monitor/default_tolerance_seconds` | `7200` | ソース側の上書きが無いときの実行遅延の猶予 |
| `/monitor/retention_days` | `14` | source_run_log の保持日数（自動 prune） |
| `/monitor/error_streak_threshold` | `1` | `/healthz/source/:id` を 503 にする連続エラー回数。**ソース側で上書き可** |
| `/monitor/sample_size` | `50` | 統計・streak の算出に使う直近 run 件数 |

ソース定義側で上書きできるキー:

| キー | 意味 |
|------|------|
| `/monitor/tolerance` | 実行遅延の猶予。文字列なら `'30m'` のような Rufus 形式、数値なら秒。既定は `/monitor/default_tolerance_seconds` |
| `/monitor/silence_tolerance` | 無配信の許容期間。**未指定ならサイレント不発を検知しない**（opt-in） |
| `/monitor/error_streak_threshold` | 503 にする連続エラー回数。既定は `/monitor/error_streak_threshold`（#1558） |

`silence_tolerance` はソースの性格に合わせて宣言する。年単位で正常に静かなソースに短い値を置くと過検知になる。**過検知は監視の信頼を壊す**ので、観測された最大の無配信間隔を上回る側に丸める。

```yaml
# 週次で必ず何か出るはずのソース
monitor:
  tolerance: 30m
  silence_tolerance: 30d
```

#### `error_streak_threshold` の上書き (#1558)

⚠ **外部の安定度はソースの性質。**YouTube の `feeds/videos.xml` は**チャンネルが生きていても 24h で 7〜10% 失敗する**一方、GitHub の `releases.atom` は 0%。グローバル値だけだと、上げれば安定したソースの検知が鈍り、下げようもない。

🔴 **グローバル値だけだった間、この調整は Uptime Kuma の `maxretries` へ漏れ出していた。**⚠ **ソース定義を読んでも「何回で赤くなるか」が分からない**状態になるので、道具側に置く。

```yaml
# 取得元が間欠的に失敗するソース
monitor:
  error_streak_threshold: 4
  silence_tolerance: 90d
```

⚠⚠ **緩めても「本当に死んだら赤くなる」ことは変えない。**`cron: '0,15,30,45 * * * *'` なら 4 連続＝**1 時間で赤**。エラー率 7.3% なら 4 連続失敗の確率は 0.003% で、偽陽性はほぼ消える。

⚠ **読む行数（`streak_window`）も一緒に広がる。**`sample_size` より大きいしきい値を書いても窓が足りず到達し得ない、という穴を作らないため。

⚠ **opt-in なので「書き忘れ」と「意図的に検知しない」が設定上は区別できない。**`bin/shrieker source validate` は監視対象なのに `silence_tolerance` が無いソースを `WARN` として出す（スキーマ上は妥当なので `NG` にはせず、終了コードも倒さない）。年単位で静かなソースは意図的に未設定のままでよい。

### 実行ログテーブル `source_run_log`

各 source の Rufus ジョブが発火するたびに INSERT される（`migration/009`, `migration/010`）:

- `source_id`, `executed_at`, `status` (`success` | `partial` | `error`), `error_message`, `duration_ms`
- `attempted_count` / `delivered_count` — その run で配信を試みた件数 / 実際に配信できた件数
- `shrieker_errors` — shrieker (投稿先) 別のエラー件数を JSON で保持（例: `{"MastodonShrieker":2}`）。エラーが無ければ `NULL`
  - ⚠ **shrieker クラス名以外の値も入る。**宛先に一度も触れていない失敗はここへ **`UnavailableDest`**（設定はあるが Shrieker を組み立てられなかった宛先・#1504）や **`source#fetch`**（配信手前でエントリが落ちた・#1473 / #1485）として積まれる。**「どの宛先が失敗したか」と「どの処理段階が失敗したか」が同じ Hash に混在する**ので、集計を読むときは区別すること
  - 🔴 **古い行には `TomatoShrieker::FeedSource#fetch` のような旧キーが残っている。**#1485 でクラス名依存をやめて `source#fetch` に固定したが、それ以前の行はそのまま
- 古いレコードは Rufus ジョブで毎日 prune（`/monitor/retention_days`）

計上は `Source#shriek` の各 shrieker 呼び出し単位で行い、`DeliveryStats` が Mutex 越しに集約する（`IcalendarSource#exec` は `Parallel.each` で並列配信するため）。

#### run の status は `delivered_count` で決まる (#1482)

| その run のエラー | `delivered_count` | `status` | `error_streak` |
|------|------|------|------|
| なし | – | `success` | リセット |
| あり | > 0 | `partial` | **リセット** |
| あり | 0 | `error` | +1 |

⚠ **run を `error` に倒すのは 1 件も配信できなかったときだけ。**部分失敗まで `error` にすると、エントリ 1 件の webhook 失敗で `error_streak` が立ち、`error_streak_threshold: 1` のもとで**日次 cron のソースは次の run まで 24 時間 503 に貼り付く**。`SQLite3::BusyException` のように現実に起こりうる反復エラーがこの経路に乗る。

⚠ **`partial` を握り潰しているわけではない。**`error_message` と `shrieker_errors` はそのまま記録され、`/status.json` の `shrieker_errors` 集計と `last_attempted_count` / `last_delivered_count` の差から読める。

🔴 **#1504 以降、`partial` は healthz を赤にする。**上の表は `error_streak` の話であって healthz の話ではない。`partial` は定義上 `delivered_count < attempted_count`＝未達なので `undelivered` で 503 になる。**「部分失敗なら緑」と読まないこと。**解除条件も `error_streak` と違い「次の run」ではなく**「次に全宛先へ届く run」**。

⚠ **`error_rate_24h` は `status == 'error'` の割合**なので、意味は「全滅した run の割合」。部分失敗はここに出ない。

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

⚠ **`with_unbundled_env` は `RBENV_VERSION` と `PATH` は消さない。**したがって子プロセスは**本体と同じ Ruby で動き、サテライト側の `.ruby-version` は無視される**。サテライトの gem は本体と同じバージョンの gem ディレクトリに入っている必要がある（[デプロイ手順](#デプロイ手順) 参照）。

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
| GoogleNewsSource | `/source/news/phrase` | FeedSource の設定項目も利用可。`/source/news/dedupe`（デフォルト true）。`/google/news/cleaner/url` を application.yaml に設定すると [google-news-rss-cleaner](https://github.com/pooza/google-news-rss-cleaner) 経由で実記事 URL に解決し、Google News が古記事に付ける fresh pubDate 問題も併せて回避する |
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
| WebhookShrieker | `/dest/hooks` | Slack Incoming Webhooks 互換の宛先の配列（Discord は末尾に `/slack`）。URL 文字列のほかオブジェクト形式も可 → [Webhook 宛先の指定形式](#webhook-宛先の指定形式) |
| LineShrieker | `/dest/line/user_id`, `/dest/line/token` | チャンネルアクセストークン（長期） |
| PieFedShrieker | `/dest/piefed/url`, `/dest/piefed/access_token`, `/dest/piefed/community_name` | `/dest/piefed/api_version`（デフォルト alpha） |
| NostrShrieker | `/dest/nostr/private_key` | nsec 形式対応。リレーは `/nostr/relays`（application.yaml） |

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

### 6. 外部リポジトリ・外部システムの同期確認

#### ginseng-* のピン棚卸し

🔴 **毎回必ず実行する。**`Gemfile.lock` は git 参照のリビジョンを固定するので、**放っておくと何ヶ月も進まず、security 修正だけが届かない状態になる**。2026-08-21 の sync では `ginseng-core` が **82 コミット遅れ**（1.15.28 → 1.19.0）で、SSRF 対策・ログの資格情報スクラブが丸ごと未達だった。⚠ **この手順が空だったことが原因**。

⚠ **サテライト 3 本（`loquat` / `shooby-do-bop` / `dqdai-anniv`）も対象。**本体だけ追随すると CommandSource の 7 ソースだけ古い gem で動き続ける。

🔴 **tomato 自身は `origin/develop` から読む (#1550)。**⚠ **`origin/HEAD` は `main` ＝ リリース済みの版**で、日常の作業は `develop`。main と develop でピンが違う期間、`origin/HEAD` を読むと**すでに `develop` で追随済みのものをもう一度上げようとするか、`develop` 側の乖離を見落とす**。⚠ **サテライト 3 本はそれぞれの default ブランチのまま**（`shooby-do-bop` は `master`）。

🔴 **作業ツリーの `Gemfile.lock` を読んではいけない。**チェックアウトが古い feature ブランチに乗っていると、**そのブランチのピンを現状と誤読する**。2026-08-25 の sync では、サテライト 3 本が `chore/*-ginseng-style` に乗っていたせいで **ahead=103（実際は 21）** と出て、追随済みのものを未追随と誤判定しかけた。**必ず追跡ブランチから取り出す**（上記のとおり tomato は `origin/develop`、サテライトは `origin/HEAD`）。

```sh
for d in tomato-shrieker loquat shooby-do-bop dqdai-anniv; do
  # ⚠ tomato 自身だけ develop。origin/HEAD は main ＝ リリース済みの版 (#1550)
  ref=origin/HEAD; [ "$d" = tomato-shrieker ] && ref=origin/develop
  git -C ~/repos/$d fetch -q origin
  git -C ~/repos/$d show $ref:Gemfile.lock |
  awk '/github\.com\/pooza\/ginseng-/{g=$2; sub(/.*\//,"",g); sub(/\.git/,"",g); f=1} f&&/revision:/{print g, $2; f=0}' |
  while read -r gem rev; do
    ahead=$(gh api repos/pooza/$gem/compare/$rev...main --jq .ahead_by 2>/dev/null)
    printf '%-16s %-18s %s\n' "$d" "$gem" "${ahead:-?}"
  done
done
```

遅れがあれば `bundle update <gem>` で追随する。⚠ **ルーチンの `Gemfile.lock` 最新化は PR 不要・`develop` 直コミットでよい**（[ginseng-style の workflow.md](https://github.com/pooza/ginseng-style/blob/main/docs/workflow.md)）。ただし**溜めてから一気に追随するときは単独 PR にして、本番で挙動を観察する**。

⚠ **追随で「必須の設定キー」が増えていることがある。**実例: ginseng-core 1.19.0 の `HTTP#initialize` は `/http/timeout/seconds` を読み、`/http/retry/max_seconds` と違って**既定へ倒れない**。無いと HTTP を作った時点で `ConfigError` になる（本体・サテライトとも `30` を設定済み）。**必ずローカルで `rake test` を通してから push する。**

#### サテライト 3 本の open PR / issue と CI

🔴 **毎回実行する。**`loquat` / `shooby-do-bop` / `dqdai-anniv` は **CommandSource の 7 ソースの実体**だが、tomato 側からは見えないので**放置されても誰も気づかない**。⚠ **上流（`ginseng-style` / `ginseng-*`）はこちらへ PR / Issue を送ってくるので、受け取りが止まると横断の変更がここで詰まる。**

```sh
for d in loquat shooby-do-bop dqdai-anniv; do
  b=$(gh repo view pooza/$d --json defaultBranchRef --jq .defaultBranchRef.name)
  echo "=== $d ($b) ==="
  gh pr list -R pooza/$d --state open
  gh issue list -R pooza/$d --state open
  gh run list -R pooza/$d -b $b -L 1 --json conclusion,headSha --jq '.[]|"CI \(.conclusion) \(.headSha[0:7])"'
done
```

🔴 **2026-08-25 の実測では 3 本とも default ブランチの CI が赤で、上流からの PR が 6 日間止まっていた。**⚠ **`dqdai-anniv` は TZ 依存のバグ（[#32](https://github.com/pooza/dqdai-anniv/issues/32)）で 4 日以上赤のまま**で、それが上流の PR まで巻き添えにしていた。

⚠ **上流から届いた PR がブランチを切った時点より default が進んでいることがある。**`chore/*-ginseng-style` は `/http/timeout/seconds` の設定より前から出ていたので、**そのままでは CI が `ConfigError` で落ちる**。**default をマージしてから通す。**

#### Kuma のモニターと有効ソースの突き合わせ

🔴 **毎回実行する。**総合 `/healthz` は `undelivered` / `silent` を見ないので（#1508）、**Kuma に登録されていないソースは、配信が止まっていても誰も気づかない**。⚠ **登録は UI での手作業で自動化が無い**ため、ソースを足すたびに漏れうる。

📌 **2026-09-05 時点で 56 ソース / 56 モニターが一致し、全部 active。**（2026-08-21 は 39 に対し 24＝15 ソースが不可視だった。）**「登録を義務づける運用」で塞ぐ**という #1508 の案 A が成立している状態なので、**この突き合わせがその唯一の担保**になる。

```sh
diff <(ssh oscura 'curl -s http://127.0.0.1:4567/status.json' | jq -r '.sources[].id' | sort) \
     <(ssh mucor 'sudo docker exec uptime-kuma sqlite3 -readonly /app/data/kuma.db \
        "select name from monitor where name like \"tomato-shrieker %\";"' | sed 's/^tomato-shrieker //' | sort)
```

- `<` の行 ＝ **Kuma に登録されていないソース**
- `>` の行 ＝ **Kuma にあるが本番に無いソース**（消したソースのモニターが残っている）

⚠⚠ **名前が揃っているだけでは足りない。一時停止したモニターは「登録されているが盲目」**で、上の diff には出ない。**`active` も見ること。**

```sh
ssh mucor 'sudo docker exec uptime-kuma sqlite3 -readonly /app/data/kuma.db \
  "select active, count(*) from monitor where name like \"tomato-shrieker %\" group by active;"'
```

⚠ **`interval` / `maxretries` のばらつきも読む。**⚠⚠ **ここに散らばりがあるのは、ソース側に置けない調整が Kuma へ漏れ出している印**（#1558）。2026-09-05 の実測は `interval` が 300s×35 / 900s×4 / 1800s×17、`maxretries` が 0×35 / 2×21 で、**2 が付いている 21 本＝ YouTube 4 本＋新規リポジトリ 17 本**＝外部が不安定なぶんを Kuma 側で吸収している。

⚠ **機械的に全部足すのが正解とは限らない。**モニターが増えると Kuma 側（SQLite の単一ライタ）が詰まるので、[chubo2 の infra-note](https://github.com/pooza/chubo2/blob/main/docs/infra-note.md) のチェック間隔ティア分けに沿って、**赤で気づきたいものを選んで足す**。

#### 上流への差し戻し

⚠ **アプリ側で回避策を持たない。**gem を直せば済むと分かったら、**該当 gem のリポジトリに Issue を立てる**。横断の話（RuboCop 設定・規約・CI）は [pooza/ginseng-style](https://github.com/pooza/ginseng-style) へ。ginseng-* は自走しており、Issue / PR は埋もれない。

> **TODO**: chubo2 インフラノート（`pooza/chubo2` の `docs/infra-note.md`）との連携が整ったタイミングで手順を追加する。

### 7. マイルストーンの状態確認

- `docs/CLAUDE.md` と MEMORY.md に記載された次期マイルストーンの Issue が、実際の GitHub 上の状態（open/closed）と一致しているか確認
- クローズ済みの Issue があれば MEMORY.md から除外し、`docs/CLAUDE.md` も必要に応じて更新

### 8. MEMORY.md の更新

- 上記で検出した差分（Issue 状態、リリース日の誤り、件数のズレ等）を反映

### 9. 同期結果の報告

- 現在のブランチ・状態、マイルストーンの状況、各確認項目の結果をまとめて報告する

## 情報の記載先ルール

⚠ **「課題・タスクは Issue で管理する」「docs に書くだけでは管理されていない扱い」は [workflow.md](https://github.com/pooza/ginseng-style/blob/main/docs/workflow.md) が正本。**tomato 固有はこの 2 つ。

- **プロジェクト共有すべき知見** → `docs/CLAUDE.md` など git 管理下のファイルに記載する。⚠ **メモリにだけ置かない**
- **進捗の同期** → `MEMORY.md` だけでなく `docs/CLAUDE.md` も更新すること。特にリリース済みバージョンの反映（「開発中」→「リリース済み」への変更）を忘れないこと

## 関連リポジトリ

- [ginseng-core](https://github.com/pooza/ginseng-core) — 基盤ライブラリ（branch: main）
- [ginseng-fediverse](https://github.com/pooza/ginseng-fediverse) — Fediverse 対応
- [ginseng-youtube](https://github.com/pooza/ginseng-youtube) — YouTube 対応
- [mulukhiya-toot-proxy](https://github.com/pooza/mulukhiya-toot-proxy) — 姉妹プロジェクト（構成が類似）
- [google-news-rss-cleaner](https://github.com/pooza/google-news-rss-cleaner) — Google News redirect URL 解決ツール（kues 上で systemd 稼働、Node.js + Playwright）。tomato-shrieker の管理対象に含む
- [chubo2](https://github.com/pooza/chubo2) — itamae ベースの構成管理。インフラ課題の issue 管理先
