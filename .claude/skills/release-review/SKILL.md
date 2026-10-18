---
name: release-review
description: リリース前レビュー。マイルストーンの Issue を消化した後、5 観点（セキュリティ・設定と宛先契約・スケジューラとライフサイクル・エラー処理と観測性・規約）をサブエージェントで並列に走らせて指摘を合流させる。ユーザーが明示したときだけ使う。
disable-model-invocation: true
---

# リリース前レビュー

⚠ **この手順の正本はこのファイル**（#1577 で `docs/CLAUDE.md`「リリース前レビュー」から移した）。
⚠ **外へ書く step を含む**（黄・緑の指摘の Issue 起票）ので明示呼び出しに限ってある（[ginseng-style の docs/skills.md](https://github.com/pooza/ginseng-style/blob/main/docs/skills.md)）。

各マイルストーンの Issue が消化済みになった後、リリース PR を作る前に実施する。**単一のセキュリティレビューだけでは実用上の問題が取りこぼされる**ため、以下 5 観点を独立したサブエージェントで並列に走らせ、指摘を合流させる（モロヘイヤ／capsicum で先行運用しているプラクティスの移植）。

| 観点 | 焦点 |
| --- | --- |
| セキュリティ | `/security-review` スキル。Webhook URL/トークン取り扱い・暗号化・Sentry/ログのシークレット scrub・フィード入力（RSS/nokogiri パース）の検証 |
| 設定・宛先契約 | ソース定義 YAML スキーマ整合（`config/schema/source.yaml`・`base.yaml`）・各 Shrieker の dest 解釈・ginseng-fediverse/piefed/youtube interface・本家 API（Mastodon/Misskey/Nostr/LINE/Matrix/PieFed）呼び出しの正確性・ソース定義リファレンスや `/healthz` 仕様との齟齬 |
| スケジューラ・ライフサイクル | rufus-scheduler の cron 駆動・`scheduler_daemon`・`source_run_log`・Entry の重複判定と管理・Sequel 接続・CommandSource 子プロセス実行・oscura（Ubuntu / systemd）の daemon 駆動 |
| エラー処理・観測性 | Sentry 計装（source/shrieker タグ）・`Ginseng::GatewayError` の scrub・`/healthz` の error_streak / WARN/NG 判定・ログの本文/個人情報漏洩チェック |
| コーディングスタイル・規約整合性 | rubocop（+rubocop-sequel）・`rake config:lint`・設定のスラッシュ記法・2 スペースインデント・廃止語（lemmy 等） |

対象範囲は `v<前リリース>..develop` の差分。

⚠ **上の 5 観点のうち共通なのは「セキュリティ」「エラー処理・観測性」「コーディングスタイル・規約整合性」の 3 つ**で、[ginseng-style の workflow.md](https://github.com/pooza/ginseng-style/blob/main/docs/workflow.md) にも同じものがある。**「設定・宛先契約」「スケジューラ・ライフサイクル」が tomato 固有**の観点。

## 走らせ方

- 🔴 **Codex（`chatgpt-codex-connector[bot]`）を必ず併走させる。**PR ready 時に走るので、重複しない指摘だけを拾う。⚠ **5 観点はロジック・契約寄り、Codex はスキーマの網羅性に強い**（4.3.0 では 5 観点が見落とした P2 を 2 件 Codex が検出した）。結果の読み方は [sync スキル](../sync/SKILL.md) の 4.
- ⚠ **エージェントの指摘は実機で裏を取る。**断定調で返ってきても誤検知がある（4.3.0 の「disable の二重キーは後勝ちで無害」は実機で覆った）
- 🔴 **「本番の実データで確かめよ」と指示すると桁違いに強い。**oscura の DB を**読み取り専用**で叩かせると、マイグレーションの影響や過検知の件数が数値で出て、そのままデプロイ判断になる（4.6.0）。⚠⚠ **読ませてよいのは DB と `/status.json` まで。本番の `config/local.yaml` / `config/sources/` には資格情報が入っているので読ませない**
- ⚠ **同じ指摘を複数の観点が独立に出すのは無駄ではなく確度の証拠。**

### エージェントへの指示の型

5 本とも同じ前提を書く。どれも、書かなかったときに実際に起きた。

- 🔴 **`rake test` / `bin/test.rb` を走らせない。**DB を共有しているので互いを壊す（[docs/CLAUDE.md](../../../docs/CLAUDE.md) の「テストの罠」）。挙動は `bundle exec ruby -e` などの一発スクリプトで、DB を書かない形で実測させる（4.16.0 では 5 本ともこれで実測して返してきた）
- 🔴 **本番では読むだけ。**DB の読み取りと `/status.json` まで。**sudo しない・一時ファイルも作らない**・git 操作や再起動をしない。⚠ 「秘密を読むな」だけでは足りない（4.12.0 では、sudo で読んだ設定から webhook の URL がコンテキストに出た）
- **各エージェントに専用の作業ディレクトリ（scratch）を渡す。**共有すると互いの一時ファイルを踏む
- **前提の版は `git show v<前>:Gemfile.lock` で確かめてから渡す。**git から取る gem は、lock の版の表記が実体とずれていることがある
- **「本番の実データで確かめよ」には、何を流すか（マイグレーション・新旧の実装）まで書く**
- 設定・宛先契約の観点には、「リリースノートに書く挙動の変化」「Wiki の追従先」「検証で確かめる項目」もまとめさせる。リリースノートとリリース前検証の材料になる

### 裏取りの型: 本番 DB を複製して手元で再生する

新旧の実装が同じデータに対して何を返すかを比べるときに使う（4.9.0 から）。

1. **複製は自分（親）が取る。**エージェントには打たせない。`ssh oscura` で `sqlite3 "file:<DB>?mode=ro"` に `.backup <一時ファイル>` を**標準入力から**流し（引数に渡すと `extra argument` で落ちる）、手元へ写して、本番の一時ファイルは消す
2. 手元の複製に、新旧のコードをそれぞれ読ませて値を比べる（旧は `git worktree` や `git archive v<前>` で展開する）
3. 終わったら複製を消す（本番の実データなので残さない）

## 指摘の行き先

⚠ **指摘の分類（赤＝必修 / 黄＝余力があれば / 緑＝送り）とその扱いは [workflow.md](https://github.com/pooza/ginseng-style/blob/main/docs/workflow.md) が正本。**必要最小限（赤）のみ本リリースで対応し、残りは Issue 起票して次リリース以降へ送る。

⚠ **起票したらその場でマイルストーンとサイズラベルを振る**（未割当は「振り忘れ」だけを意味する＝[sync スキル](../sync/SKILL.md) の 7.）。
