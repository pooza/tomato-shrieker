---
name: doc-maintenance
description: docs / スキル / メモリ / Wiki の棚卸し。「棚卸しして」「ドキュメントの陳腐化を見直して」で回す。陳腐化の改善・メモリ→docs の昇格・docs→メモリの退避・公開リポジトリに載った内部情報の移設・役目を終えた記述のアーカイブ・1 回で読めない大きさのファイルを詰める・Wiki との食い違い。不定期・オンデマンド。
disable-model-invocation: true
---

# docs・スキル・メモリ・Wiki の棚卸し

**不定期・オンデマンド**で回す整備作業。定期トリガー（cron / 毎リリース）は設けない。⚠ 毎リリースで回す追従（docs と Wiki）は [release スキル](../release/SKILL.md) の 8. / 9. にある。こちらは**リリースの追従では拾えない、溜まっていく腐り**を回収する。

⚠ **土台は capsicum の `/doc-maintenance`**（[pooza/capsicum](https://github.com/pooza/capsicum) の `.claude/skills/doc-maintenance/SKILL.md`）。tomato では前提が 3 点違うので、そのまま踏襲しない。

| | capsicum | tomato |
| --- | --- | --- |
| 大きさの検出 | CI のガードが毎回見る | **ガードが無い**＝この棚卸しで測るしかない |
| 利用者向けの正本 | docs | **Wiki**（`~/repos/tomato-shrieker.wiki`）。docs は開発者向け |
| 手順の置き場 | スキルと docs に分かれる | **手順はスキル**（#1577）、判断と構造は docs |

⚠ **外へ書く step を含む**（docs の commit・Wiki の push・chubo2 への PR）ので、明示呼び出しに限ってある（[ginseng-style の docs/skills.md](https://github.com/pooza/ginseng-style/blob/main/docs/skills.md)）。**直す前に、見つけたものを一覧にして報告し、判断を仰ぐ。**

## 対象

- `docs/*.md`（開発者向けの正本・`CLAUDE.md` だけが自動ロードされる）
- `.claude/skills/*/SKILL.md` と同梱の `scripts/`・`sources/`
- メモリ（`~/.claude/projects/-home-pooza-repos-tomato-shrieker/memory/`・Google Drive で端末間共有・**`MEMORY.md` も自動ロードされる**）
- Wiki（利用者向けの正本）

## 手順

### 1. 陳腐化

- docs とスキルを通読し、もう成り立たない記述を洗う。grep の手がかり:

  ```sh
  grep -rn -E '予定|未実装|当面|将来|現時点|で対応|#[0-9]{4} で|まだ' docs .claude/skills --include='*.md'
  ```

- ⚠ **issue 番号を名指しした「〜は #NNNN で」は、その issue の状態を引いてから直す。**閉じていれば、書き方を「済んだ形」に改める（4.17.0 のレビューで、閉じる直前の #1529 を「同期で受け取る手段は #1529」と書いた行が 2 か所残っていた）

  ```sh
  grep -rhoE '#1[0-9]{3}' docs .claude/skills | sort -u | sed 's/#//' \
    | xargs -I{} gh api repos/pooza/tomato-shrieker/issues/{} --jq '"#\(.number) \(.state)"' | grep closed
  ```

  ⚠ 閉じた issue の番号は、経緯の出典として残っているのが普通。**「これから」と読める文脈のものだけ**が直す対象
- 本番・旧本番・移設済みのホストについての記述は、いまの構成と合っているかを見る（本番は seas → oscura へ移った。[[project_oscura_migration]]）
- **必ずコード・GitHub・本番の読み取りで裏を取ってから直す。**推測で断定しない

### 2. メモリ → docs（共有すべき知見の昇格）

📌 **tomato のメモリは「docs を優先」する**（[[feedback_share_to_docs]]）。メモリだけにある情報は最小限にする。

- メモリを走査し、**全端末と人間にも役立つ一般的な知見**（規約・手順・再発する技術的な罠）で、**非公開の情報を含まない**ものを拾う
- 行き先: 技術的な罠・設計の理由 → 該当する `docs/*.md`、手順 → 該当する**スキル**、毎回読む必要がある方針 → `docs/CLAUDE.md`
- 移したら、メモリ側は消すか、ポインタと非自明な点だけを残す
- **昇格しない**: feedback（Claude 向けの作業ルール）・端末固有の値・特定の運用者の判断や経緯・本番の実測値のスナップショット
- ⚠ **`MEMORY.md` の大きさも見る。**自動ロードされるので、太るとセッションごとのコストになる。「現在の状態」の節は sync のたびに書き換えるもので、済んだ項目は消す（トピックファイルに移す）

### 3. docs → メモリ（プライベートな記述の退避）

- docs・スキル・同梱ファイルから、公開リポジトリに載せるべきでない記述を拾う: 資格情報やその在りか、個人のアカウント（メールアドレスなど）、端末固有の値、運用者の私的な判断
- メモリの `reference_*` / `project_*` へ移し、docs 側は一般的な書き方に置き換える

### 4. 公開境界（インフラの内部情報）

🔴 **tomato-shrieker は公開リポジトリ。**サーバーの内部情報の正本は chubo2（private）の `docs/infra-note.md`。

```sh
git grep -n -I -E 'b-shock\.local|b-shock\.co\.jp|deploy@|/home/deploy|192\.168\.|100\.[0-9]+\.[0-9]+\.[0-9]+|Tailscale|Linode' -- docs .claude README.md
```

- **IP アドレス・VPN の構成・ホスティング業者・LAN のホスト名で作業に要らないもの**は、infra-note へ寄せて剥がす（infra-note に既にあれば剥がすだけ）
- ⚠ **deploy / sync の同梱スクリプトが叩く本番のホスト名（`ssh oscura`）と `deploy` ユーザーは、手順が動くために要る。**📌 **残すとユーザーが決めた**（2026-10-18・LAN の外からは名前解決できない）。この判断は繰り返さない
- infra-note は別リポジトリなので、変更は chubo2 への PR にする

### 5. 役目を終えた記述のアーカイブ

- 現役で参照しないが、経緯として残す価値があるもの（完了した計画・廃止したホストの節・決着した検討）を `docs/archive/` へ移す（例: [v4-plan.md](../../../docs/archive/v4-plan.md)）
- 移したら、参照元のリンクを直し、ファイルの冒頭に「アーカイブ（現役運用では参照しない）」と書く
- ⚠ **「再提案しない」「採らない」と書いた決定は、結論を本体に残す。**丸ごと退かすと、再提案を止めていた記述が「参照しない場所」へ落ちる
- ⚠ **コードのコメントや docs どうしが節の名前で参照していないかを先に引く**（リンクではなく本文の文字列なので、壊れてもどの検査にもかからない）

  ```sh
  grep -rn '<ファイル名や節の名前>' app bin test docs .claude --include='*.rb' --include='*.md'
  ```

### 6. 1 ファイルの大きさ

**目安は 60,000 バイト**（capsicum と同じ。1 回の Read で読み切れる大きさ）。⚠ **tomato には CI のガードが無い**ので、ここで測る。

```sh
wc -c docs/*.md .claude/skills/*/SKILL.md | sort -rn | head
```

- 超えた・迫っているファイルは、**1 回に 1 本**、大きい順に詰める
- **決着した節** → `docs/archive/<元の名前>-settled.md` へ移し、本体には見出しと結論だけを残す
- **決着しない節**（落とし穴集・進行中の設計） → 別ファイルへ分け、`docs/CLAUDE.md` の表に行き先を足す
- ⚠ **閾値の直下で止めない。**次の 1 段落で超えるので、余白を残すところまでやる
- ⚠ [[feedback_claude_md_size]]: `docs/CLAUDE.md` は 500〜600 行が目安。大きくなる前に分割を相談する

### 7. Wiki との食い違い（tomato 固有）

**Wiki が利用者向けの正本**で、追従はリリースのたび（release スキルの 9.）。⚠ ただしリリース単位の追従は「そのリリースで変えた機能」しか見ないので、**古い版から残った食い違いは拾えない**（4.6.0 の時点で「監視」が 4.2.0 相当のまま放置されていた）。

```sh
git -C ~/repos/tomato-shrieker.wiki pull
grep -rn -E '[0-9]+\.[0-9]+\.[0-9]+ ?(から|〜|まで)' ~/repos/tomato-shrieker.wiki/*.md | wc -l   # 版つきの注記の量
```

- 監視・コマンドラインツール・設定ファイル・アップデート手順・各ソース / Shrieker のページを、docs とコードに照らして読む
- **古い版の注記**（「4.8.0 までは…」）が積み上がって読みにくくなっていたら、現役の利用者に要らないものを畳む（アップデート手順の版ごとの節は残す）
- Wiki は `master` へ直接 push する

## 実施後

- docs とスキルの変更は PR にする（develop 向け）。メモリは Google Drive で同期されるので commit は要らない。Wiki は push、infra-note は chubo2 への PR
- 大きく動かしたら、`docs/CLAUDE.md` の表（どの docs をいつ読むか）・`MEMORY.md` の索引・`[[リンク]]` の整合を確かめる
- 見送ったもの・ユーザーと決めたことは、次の棚卸しで同じ判断を繰り返さないよう、この SKILL.md か `MEMORY.md` に 1 行で残す
