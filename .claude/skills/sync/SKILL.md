---
name: sync
description: セッション開始時の進捗同期。「進捗を同期してください」「同期して」などで起動する。リモート・Dependabot・Codex レビュー・Sentry・ginseng-* のピン・サテライト 3 本・Kuma との突き合わせ・マイルストーンを確認して報告する。
---

# セッション開始時の同期手順

🔴 **会話の最初に「進捗を同期してください」等の指示があったら、この手順を実行する。**

⚠ **この手順の正本はこのファイル**（#1577 で `docs/sync.md` から移した）。手順の中のコマンドは `scripts/` に同梱してあり、**リポジトリのルートから `.claude/skills/sync/scripts/<名前>.sh` で実行する**。
⚠ 読むだけの手順なので自動起動にしてある（[ginseng-style の docs/skills.md](https://github.com/pooza/ginseng-style/blob/main/docs/skills.md)）。**途中で外へ書くもの（Sentry へのコメント・Issue 起票・`Gemfile.lock` の追随の push）は、報告して判断を仰いでから行う。**

## 1. プロジェクトガイドの読み込み

- `docs/CLAUDE.md` を読む（プロジェクトのルール・構造・履歴の正本）
- 🔴 **`docs/` は 1 本ではない。**触る領域に応じて [monitoring.md](../../../docs/monitoring.md) / [sources.md](../../../docs/sources.md) / [daemon.md](../../../docs/daemon.md) も開く。⚠⚠ **自動ロードされるのは `CLAUDE.md` と `MEMORY.md` だけ**なので、**「書いていない」と判断する前に `grep -rn <語> docs/` でまとめて引く**
- `MEMORY.md` は自動ロードされるので、両者の整合性を意識する

## 2. リモートとの同期・状態確認

- `git fetch origin` — **最初に必ず実行**。リモートが正本であり、ローカルの状態を信用しない
- `git log HEAD..origin/develop --oneline` — リモートに未取り込みのコミットがないか確認。差分があればpullを検討
- `git log --oneline -10` — 直近のコミット履歴
- `gh issue list --state open` — open Issue一覧
- `gh pr list --state open` — open PR一覧

## 3. Dependabotセキュリティアラート

- `gh api repos/pooza/tomato-shrieker/dependabot/alerts` で open アラートを確認
- 0件なら対応不要、あれば提案

## 4. Codexレビューコメントの確認

⚠ **採否の判断・返信の作法・待ち方の正本は [ginseng-style の codex-review スキル](https://github.com/pooza/ginseng-style/blob/main/plugins/ginseng/skills/codex-review/SKILL.md)。**ここに書き写さない。sync で見るのは「取り残しが無いか」だけ。

- `.claude/skills/sync/scripts/codex_channels.sh` で、最近マージされた PR 5 本について下の 4 経路を読む（PR 番号を渡せばその PR だけ）
- 🔴 **返信と 👍 / 👎 の両方が付いていないものは未処理。**内容を確認し、対応が必要か判断する

🔴 **Codex の結果は 4 経路で来る。全部読む (#1618)。**⚠⚠ **「指摘なし」はコメントでも review でもなく、PR 本体への 👍 リアクションで来る。**`pulls/{n}/comments`（インライン）だけを見ていると、**走査済みなのに「まだ来ていない」と読んで待ち続ける**（#1617 で 50 分待った）うえ、review 本文や issue コメントで来た指摘を取りこぼす。

⚠ **👍 は「この PR に指摘が無かった」ではなく「ある巡が指摘なしで終わった」だけ。**指摘が出た PR にも後の巡で付くので、インラインは別に見る。2 巡目以降を待つときの基点の採り方は codex-review スキルの側にある。

## 5. Sentry の新規イシュー確認

- `sentry-cli issues list` で未解決イシューを確認する（`~/.sentryclirc` に認証トークンとデフォルトプロジェクトが設定済み）
- 各イシューの過去コメント（対応経緯）を確認する: `curl -sH "Authorization: Bearer $TOKEN" https://sentry.io/api/0/issues/{issue_id}/comments/ | python3 -m json.tool`
- 新規・未解決のイシューがあれば内容を確認し、対応が必要か判断する（対応が必要なら GitHub Issue を起票）
- 判断結果や対応経緯はコメントとして記録する: `curl -sX POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"text":"コメント内容"}' https://sentry.io/api/0/issues/{issue_id}/comments/`
- `$TOKEN` は `~/.sentryclirc` の `[auth]` セクションから取得する
- Sentry 未導入のプロジェクトではこのステップをスキップする

## 6. 外部リポジトリ・外部システムの同期確認

### ginseng-* のピン棚卸し

🔴 **毎回必ず実行する。**`Gemfile.lock` は git 参照のリビジョンを固定するので、**放っておくと何ヶ月も進まず、security 修正だけが届かない状態になる**。2026-08-21 の sync では `ginseng-core` が **82 コミット遅れ**（1.15.28 → 1.19.0）で、SSRF 対策・ログの資格情報スクラブが丸ごと未達だった。⚠ **この手順が空だったことが原因**。

⚠ **サテライト 3 本（`loquat` / `shooby-do-bop` / `dqdai-anniv`）も対象。**本体だけ追随すると CommandSource の 7 ソースだけ古い gem で動き続ける。

🔴 **tomato 自身は `origin/develop` から読む (#1550)。**⚠ **`origin/HEAD` は `main` ＝ リリース済みの版**で、日常の作業は `develop`。main と develop でピンが違う期間、`origin/HEAD` を読むと**すでに `develop` で追随済みのものをもう一度上げようとするか、`develop` 側の乖離を見落とす**。⚠ **サテライト 3 本はそれぞれの default ブランチのまま**（`shooby-do-bop` は `master`）。

🔴 **作業ツリーの `Gemfile.lock` を読んではいけない。**チェックアウトが古い feature ブランチに乗っていると、**そのブランチのピンを現状と誤読する**。2026-08-25 の sync では、サテライト 3 本が `chore/*-ginseng-style` に乗っていたせいで **ahead=103（実際は 21）** と出て、追随済みのものを未追随と誤判定しかけた。**必ず追跡ブランチから取り出す**（上記のとおり tomato は `origin/develop`、サテライトは `origin/HEAD`）。

```sh
.claude/skills/sync/scripts/ginseng_pin_drift.sh
```

⚠ **タグ固定の gem（`ginseng-style` は `tag: v1.1.12` など）は main と比べない。**main には未タグのコミットが常に積まれているので、比べると**追随済みでも「6 件遅れ」のように出る**（2026-09-17 まで実際にそう出ていた）。最新タグと比べ、違えば `v1.1.11 → v1.1.12` の形で出す。追随は Gemfile の `tag:` を書き換える。

遅れがあれば `bundle update <gem> --patch` で追随する。⚠ **`--patch` を付ける。**付けないと ginseng の依存まで上がる（2026-09-17 の実測: net-protocol 0.3 → 0.4、サテライトでは json 2 → 3）。⚠ **`--conservative` は使わない。**git ソースの version 行が古いまま残って lock が壊れる（`Could not find ginseng-core-1.23.5 ... at main@b6e736d`）。⚠ **ルーチンの `Gemfile.lock` 最新化は PR 不要・`develop` 直コミットでよい**（[ginseng-style の workflow.md](https://github.com/pooza/ginseng-style/blob/main/docs/workflow.md)）。ただし**溜めてから一気に追随するときは単独 PR にして、本番で挙動を観察する**。

🔴 **`--patch` は `branch:` の git ソースを抑えない (#1618)。**⚠⚠ git ソースは常にブランチ先頭を取るので、**メジャーを跨いでも止まらない**。しかも上の棚卸しの出力は**コミット数**なので、**メジャーを跨いだことはどこにも出ない**（2026-09-21 に `ginseng-fediverse` が 2.0.0 → 3.1.0 になり、出力は `7` だった）。**追随したら新旧の version を必ず読む。**

```sh
git diff Gemfile.lock | grep -A2 'ginseng-' | grep -E '^[-+] +ginseng-'
```

メジャーが動いていたら、**跨いだリリースノートを全部**読み（「破壊的変更」「breaking」の節）、利用側の追随が要るかを判断してから push する。⚠⚠ **最新の 1 件だけ読んではいけない。**2.0.0 → 3.1.0 なら破壊的変更は間の **3.0.0** に書いてある。⚠ リリースは作成順に並び、旧系列の修正版（2.0.x）が間に挟まるので、**版の範囲で絞る**。

```sh
.claude/skills/sync/scripts/release_notes.sh ginseng-fediverse 2.0.0 3.1.0  # 上の差分の - と + の版
```

⚠ **追随前に分かるなら先に読む。**`gh api repos/pooza/<gem>/releases --jq '.[0:3][]|.tag_name'` で最新タグを見れば、棚卸しの段階でメジャーの有無は分かる。

⚠ **追随で「必須の設定キー」が増えていることがある。**実例: ginseng-core 1.19.0 の `HTTP#initialize` は `/http/timeout/seconds` を読み、`/http/retry/max_seconds` と違って**既定へ倒れない**。無いと HTTP を作った時点で `ConfigError` になる（本体・サテライトとも `30` を設定済み）。**必ずローカルで `rake test` を通してから push する。**

🔴 **ただしサテライト 2 本はローカルでは緑にならない。**⚠⚠ **この赤を「追随で壊した」と読み違えないこと。**

| リポジトリ | ローカルの結果 | 理由 |
| --- | --- | --- |
| `loquat` | **10 errors** | `localhost:8888` の録画サーバが開発機に無い |
| `shooby-do-bop` | **3 errors** | `/google/api/key`（YouTube API キー）が開発機に無い |
| `dqdai-anniv` | 0 errors | ローカルで完結する |

⚠ **切り分け方は「bump 前の lock で同じ数の error が出るか」。**`git stash` → `bundle install` → `rake test` で突き合わせれば、環境依存か追随起因かが分かる（2026-09-23 に実施し、両方とも bump 前と同数＝環境依存と確認）。**最終的な担保は push 後の CI**（4 本とも default ブランチで走る）。

### サテライト 3 本の open PR / issue と CI

🔴 **毎回実行する。**`loquat` / `shooby-do-bop` / `dqdai-anniv` は **CommandSource の 7 ソースの実体**だが、tomato 側からは見えないので**放置されても誰も気づかない**。⚠ **上流（`ginseng-style` / `ginseng-*`）はこちらへ PR / Issue を送ってくるので、受け取りが止まると横断の変更がここで詰まる。**

```sh
.claude/skills/sync/scripts/satellites.sh
```

🔴 **2026-08-25 の実測では 3 本とも default ブランチの CI が赤で、上流からの PR が 6 日間止まっていた。**⚠ **`dqdai-anniv` は TZ 依存のバグ（[#32](https://github.com/pooza/dqdai-anniv/issues/32)）で 4 日以上赤のまま**で、それが上流の PR まで巻き添えにしていた。

⚠ **上流から届いた PR がブランチを切った時点より default が進んでいることがある。**`chore/*-ginseng-style` は `/http/timeout/seconds` の設定より前から出ていたので、**そのままでは CI が `ConfigError` で落ちる**。**default をマージしてから通す。**

### Kuma のモニターと有効ソースの突き合わせ

🔴 **毎回実行する。**総合 `/healthz` は `undelivered` / `silent` を見ないので（#1508）、**Kuma に登録されていないソースは、配信が止まっていても誰も気づかない**。⚠ **登録は UI での手作業で自動化が無い**ため、ソースを足すたびに漏れうる。

📌 **2026-09-05 時点で 56 ソース / 56 モニターが一致し、全部 active。**（2026-08-21 は 39 に対し 24＝15 ソースが不可視だった。）**「登録を義務づける運用」で塞ぐ**という #1508 の案 A が成立している状態なので、**この突き合わせがその唯一の担保**になる。

```sh
.claude/skills/sync/scripts/kuma_diff.sh
```

- `<` の行 ＝ **Kuma に登録されていないソース**
- `>` の行 ＝ **Kuma にあるが本番に無いソース**（消したソースのモニターが残っている）

⚠⚠ **名前が揃っているだけでは足りない。一時停止したモニターは「登録されているが盲目」**で、diff には出ない。**スクリプトが続けて出す `active` の内訳も見ること。**

🔴 **ソース側へ `error_streak_threshold` を移したら、そのモニターの `maxretries` は 0 に戻す (#1558)。**⚠⚠ **両方残すと猶予が掛け算になる**（ソース側 N run × Kuma の再試行）。⚠ Kuma の登録は UI での手作業なので、移行は 1 セットで扱うこと。

⚠ **`interval` / `maxretries` のばらつきも読む。**⚠⚠ **ここに散らばりがあるのは、ソース側に置けない調整が Kuma へ漏れ出している印**（#1558）。2026-09-05 の実測は `interval` が 300s×35 / 900s×4 / 1800s×17、`maxretries` が 0×35 / 2×21 で、**2 が付いている 21 本＝ YouTube 4 本＋新規リポジトリ 17 本**＝外部が不安定なぶんを Kuma 側で吸収している。📌 **YouTube 4 本は 2026-10-01 に 0 へ戻した（#1584）**＝しきい値はソース側の `error_streak_threshold: 28` に一本化。いまの `maxretries` は **0×39 / 2×17**。⚠ **残り 17 本は GitHub の `releases.atom`（エラー率 0%）なので漏れ出しではなく単なる余裕**＝触らない。

⚠ **機械的に全部足すのが正解とは限らない。**モニターが増えると Kuma 側（SQLite の単一ライタ）が詰まるので、[chubo2 の infra-note](https://github.com/pooza/chubo2/blob/main/docs/infra-note.md) のチェック間隔ティア分けに沿って、**赤で気づきたいものを選んで足す**。

### 上流への差し戻し

⚠ **アプリ側で回避策を持たない。**gem を直せば済むと分かったら、**該当 gem のリポジトリに Issue を立てる**。横断の話（RuboCop 設定・規約・CI）は [pooza/ginseng-style](https://github.com/pooza/ginseng-style) へ。ginseng-* は自走しており、Issue / PR は埋もれない。

> **TODO**: chubo2 インフラノート（`pooza/chubo2` の `docs/infra-note.md`）との連携が整ったタイミングで手順を追加する。

## 7. マイルストーンの状態確認

- `docs/CLAUDE.md` と MEMORY.md に記載された次期マイルストーンの Issue が、実際の GitHub 上の状態（open/closed）と一致しているか確認
- クローズ済みの Issue があれば MEMORY.md から除外し、`docs/CLAUDE.md` も必要に応じて更新

### 未割当と保留の確認

🔴 **毎回実行する。open issue は必ずどこかのマイルストーンに振る**（遠いマイナーでよい）。⚠⚠ **「意図して止めている」と「振り忘れ」がどちらも「マイルストーン無し」に見えると、振り忘れが止めているふりをして残り続ける。**2026-09-26 には未割当が 38 件溜まり、うち意図して止めていたのは 2 件だけ。しかもその 1 件（#1585「#1586 の後」）は**条件がとうに満たされていたのに誰も気づけなかった**。

- **未割当は「振り忘れ」だけを意味する。**起票したらその場でマイルストーンとサイズラベルを振る
- **意図して止めるものは `on-hold` ラベルを付け、「止めている理由」と「再開条件」をコメントに書く。**理由の無い保留は作らない。マイルストーンは外さない

```sh
.claude/skills/sync/scripts/unassigned_issues.sh
```

「未割当」が 0 件であること（出たら振る）。「on-hold」は再開条件が満たされていないかを読む。

## 8. MEMORY.md の更新

- 上記で検出した差分（Issue 状態、リリース日の誤り、件数のズレ等）を反映

## 9. 同期結果の報告

- 現在のブランチ・状態、マイルストーンの状況、各確認項目の結果をまとめて報告する
