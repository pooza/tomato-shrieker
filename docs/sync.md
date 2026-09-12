# セッション開始時の同期手順

🔴 **会話の最初に「進捗を同期してください」等の指示があったら、この手順を実行する。**

📌 **#1577 でスキル化する予定。**それまではこのファイルが正本。

### 1. プロジェクトガイドの読み込み

- `docs/CLAUDE.md` を読む（プロジェクトのルール・構造・履歴の正本）
- 🔴 **`docs/` は 1 本ではない。**触る領域に応じて [monitoring.md](monitoring.md) / [sources.md](sources.md) / [daemon.md](daemon.md) も開く。⚠⚠ **自動ロードされるのは `CLAUDE.md` と `MEMORY.md` だけ**なので、**「書いていない」と判断する前に `grep -rn <語> docs/` で 5 本まとめて引く**
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
