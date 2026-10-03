---
name: release
description: tomato-shrieker のリリース手順（develop → main の PR・タグ・リリースノート・デプロイ・docs と Wiki の追従）。ユーザーが「リリースしましょう」などと明示したときだけ使う。
disable-model-invocation: true
---

# リリース手順

⚠ **この手順の正本はこのファイル**（#1577 で `docs/CLAUDE.md`「リリースフロー」から移した）。ブランチ戦略・マイルストーンのサイズ・リリースノートの方針・Dependabot の扱いは手順ではなく文脈なので [docs/CLAUDE.md](../../../docs/CLAUDE.md) に残してある。
⚠ **外向きの操作（マージ・タグ・Release・本番デプロイ）を含む。**各段はユーザーの指示を確かめてから進める。

1. **マイルストーンの Issue をすべて消化する。**⚠ `config/application.yaml` の `/package/version` がバージョンの正本で、**着手時に bump してある**はず。違っていたらここで直す
2. **リリース前レビュー**: [release-review スキル](../release-review/SKILL.md) の 5 観点並列レビュー。必修（赤）のみ本リリースで対応し、残り（黄・緑）は Issue 起票して次リリース以降へ送る。
   ⚠⚠ **ここで必ず止まる。**`release-review` は `disable-model-invocation: true` なので、この手順からは起動できない。ユーザーに `/release-review` の実行を頼み、赤が片付くまで先へ進まない
3. **リリース前検証**: [release-validation スキル](../release-validation/SKILL.md) の手順で各 Source / Shrieker の動作を手動検証する（CI では捕まらない統合系のリグレッション検出用）。⚠ 同じ理由で、ユーザーに `/release-validation` の実行を頼む
4. **リリース PR**: `develop` → `main` へ PR を作成する。CI の緑と Codex の結果を確かめてからマージする
5. **タグとリリース**: `main` の先頭にタグを打って push し、そのタグからリリースを作る。

   ```sh
   git fetch origin && git tag vX.Y.Z origin/main && git push origin vX.Y.Z
   gh release create vX.Y.Z --verify-tag --title "X.Y.Z" --notes-file <リリースノート>
   ```

   ⚠ **`gh release create vX.Y.Z --target main` は使わない。**projects-classic 廃止の GraphQL エラーで落ちることがある。リリースノートの方針は [docs/CLAUDE.md](../../../docs/CLAUDE.md#リリースノート)
6. **デプロイ**: [deploy スキル](../deploy/SKILL.md)。⚠ **本番に出す＝リリースする。**タグを打っていない版を本番へ出さない。⚠ これも明示呼び出しなので、ユーザーに `/deploy` の実行を頼む
7. **Issue を閉じる。**⚠ `develop` 向けの PR は Issue を自動で閉じないので、マイルストーンの Issue はリリースで閉じる。マイルストーンも閉じる
8. **docs の追従**: リリースで変わった仕様が `docs/` に反映されているか確かめる
9. **[Wiki](https://github.com/pooza/tomato-shrieker/wiki) を追従させる**（クローンは `~/repos/tomato-shrieker.wiki`・ブランチは `master`）。⚠ **Wiki は利用者向けの正本。**`docs/` は開発者向けなので、両方を更新しないと利用者から見た仕様が古いまま残る

⚠ **Wiki の更新漏れは溜まりやすい。**4.6.0 の時点で「監視」ページが **4.2.0 相当**のまま放置されており、4.4.0（配信計測・サイレント不発）と 4.5.0 の変更がまるごと欠落していた。**機能を追加・変更したリリースでは、対応するページを必ず開いて確認すること。**目安:

| 変更した領域 | 追従するページ |
|------|------|
| `/healthz` `/status.json` `source_run_log` 監視設定 | 監視 |
| `bin/shrieker` のサブコマンド | コマンドラインツール |
| マイグレーション・デプロイ順序・移行作業 | アップデート手順 |
| ソース種別・投稿先・スケジュール | 各ソース／Shrieker のページ |
