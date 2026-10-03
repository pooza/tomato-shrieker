---
name: deploy
description: 本番（oscura）へのデプロイ。本体とサテライト 3 本の pull と bundle install、サービスの再起動、再起動後の確認。ユーザーが「デプロイしましょう」などと明示したときだけ使う。
disable-model-invocation: true
---

# デプロイ手順

⚠ **この手順の正本はこのファイル**（#1577 で `docs/daemon.md`「デプロイ手順」から移した）。コマンドは `scripts/` に同梱してあり、**リポジトリのルートから `.claude/skills/deploy/scripts/<名前>.sh` で実行する**。
🔴 **本番操作なので明示呼び出しに限ってある。**各段はユーザーの指示を確かめてから進める。⚠ 本番操作の一般的な注意（`deploy` ユーザーで覗く・サービス管理経由で操作する）は [docs/daemon.md](../../../docs/daemon.md#本番操作の注意) に残してある。

本番は oscura（Ubuntu / systemd）、実行ユーザー `deploy`、チェックアウトは `/home/deploy/repos/tomato-shrieker`。デプロイ対象は **`main` ブランチ**（develop は本番へデプロイしない）。🔴 **本番に出す＝リリースする。**タグを打っていない版を出さない（[release スキル](../release/SKILL.md) の 5. の後に行う）。

## 1. pull と bundle install

```sh
.claude/skills/deploy/scripts/pull.sh
```

本体と、サテライト 3 本（`loquat` / `shooby-do-bop` / `dqdai-anniv`＝CommandSource の実行対象。それぞれ独立した Gemfile を持つ）を pull し、`bundle install` する。⚠ 再起動はしない。

## 2. 再起動

```sh
ssh oscura 'sudo systemctl restart tomato-shrieker'
```

## 3. 確認

```sh
.claude/skills/deploy/scripts/verify.sh
```

読むだけ。先頭コミットと版・`ActiveState` / `NRestarts`・`/healthz`・ソースの内訳（success 以外と silent / undelivered の一覧）を出す。

- 版が上げたものになっていること、`ActiveEnterTimestamp` がいまの再起動であること、`NRestarts` が増えていないこと
- ⚠ **再起動の直後は、まだ一度も走っていないソースがある。**内訳は次の発火を待ってからもう一度読む
- ログは `/var/log/tomato-shrieker.log`

## 注意

🔴 **`bundle install` は本体・サテライトとも毎回必ず実行する。**冪等なので無駄打ちのコストはほぼ無い。省くと以下で壊れる。

- **Ruby のマイナー更新**（例: 4.0.5 → 4.0.6）で gem ディレクトリが総入れ替えになる。本体だけ `bundle install` してサテライトを忘れると、**サテライトだけが `Bundler::GemNotFound` で全滅**する（2026-08-03 に実際に発生。`loquat` / `shooby-do-bop` / `dqdai-anniv` の 7 ソースが `timecop` 欠落で 24 時間エラー）
- ginseng-\* gem は `branch: main` 追いなので、`Gemfile.lock` が同じでも中身が動く

⚠ **サテライトの `.ruby-version` は当てにならない。**scheduler_daemon の環境には `RBENV_VERSION` が入っており、それが子プロセスへそのまま継承される。つまりサテライトは自分の `.ruby-version` ではなく **本体と同じ Ruby で動く**（[CommandSource の子プロセス実行](../../../docs/CLAUDE.md#commandsource-の子プロセス実行) 参照）。`bundle install` も同じバージョンを明示して実行すること。

⚠ `git pull` を引数なしで打つと `There is no tracking information for the current branch.` で止まる。itamae の `git` リソースが upstream 追跡を持たないローカルブランチ `deploy` に着地させるため。本体は必ず **`git pull origin main`** と書く（ブランチ名が実行ユーザー名と同じなのは偶然）。

⚠ `shooby-do-bop` の既定ブランチは `master`（他は `main`）。

⚠ `config/local.yaml` と `config/sources/` は gitignore 配下＝git では上がってこない。ソース定義の正本は本番の実体で、手元の `config/sources` は dev 用。

⚠ `rake migrate` は不要（起動時に自動適用される。[daemon.md の「起動時マイグレーション」](../../../docs/daemon.md#起動時マイグレーション) 参照）。

⚠ **順序は「pull → 再起動 → CLI」で固定する。**マイグレーションを走らせるのは `SchedulerDaemon#start` だけで、`bin/shrieker` は `Sequel.connect` しかしない。再起動前に新テーブルを触るサブコマンド（`source ack` → `silence_ack`）を叩くと、Thor のエラーではなく生の `Sequel::DatabaseError: no such table` で落ちる。
