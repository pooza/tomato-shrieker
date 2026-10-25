---
name: deploy
description: 本番（oscura）へのデプロイ。本体とサテライト 3 本の pull と bundle install、再起動で増減するソースと起動で倒れる定義の確認、サービスの再起動、再起動後の確認。ユーザーが「デプロイしましょう」などと明示したときだけ使う。
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

本体と、サテライト 3 本（`loquat` / `shooby-do-bop` / `dqdai-anniv`＝コマンドを走らせるソース（CommandSource と `/source/ical/command` の IcalendarSource）の実行対象。それぞれ独立した Gemfile を持つ）を pull し、`bundle install` して `bundle check` で確かめる。⚠ 再起動はしない。

## 2. 再起動で増減するソースと、起動で倒れる定義の確認

```sh
.claude/skills/deploy/scripts/pending_sources.sh
```

読むだけ。稼働中のソース（`/status.json`）と、ディスク上の有効な定義（生の `/sources`）を突き合わせ、あわせて `source reload` の拒否と同じ検査（`SourceValidator.startup_errors`）を通す。

🔴 **再起動は、ディスクに置かれたまま reload されていないソース定義を全部読み込む。**4.13.0 のデプロイでは保留中の定義 3 件が有効になり、56 → 59 ソースになった（発火前に無効化したので投稿は出ていない）。

- `>` の行 ＝ **再起動で増えるソース**。意図したものかをユーザーに確かめる。意図していなければ `bin/shrieker source disable <id>` してから再起動する
- `<` の行 ＝ 再起動で消えるソース（定義を消した・無効にしたまま reload していない）
- `~` の行 ＝ **再起動で定義が変わるソース**（宛先やスケジュールを編集したまま reload していない・#1672）。`/status.json` の `digest`（稼働中の定義）とディスク上の定義を比べている。意図したものかをユーザーに確かめる。⚠ 稼働中の版が digest を出していない（4.17 以前）ときは比べず、そう出す
- 🔴 **`NG` が出て非 0 で終わったら、再起動しない。**起動で倒れる定義が残っている。reload が拒否された後は古いジョブが動き続けるので、稼働中の一覧は緑のまま＝再起動して初めて起動ループになる。直すか `disable` してからやり直す
- 🔴 **`BUNDLE` が出て非 0 で終わったら、再起動しない（#1477）。**コマンドを走らせるソースの `dir` で `bundle check` が通らない（または `dir` が無い）。起動は通るが、**走るたびに `Bundler::GemNotFound` で落ちる**。そのディレクトリで `bundle install` してからやり直す。⚠ daemon も登録の時点で同じ検査をして、ログと Sentry に出す（起動は止めない）
- ⚠ **NG と BUNDLE が 0 でも「起動できる」とは限らない。**見ているのはスケジュール・判別キー・コマンドの依存だけで、登録の途中で起きるほかの失敗（`command:` のソースが `bundle …` で始まるときの `bundle install` の失敗など）は見ていない。そこは 4. の `not started` の件数・`NRestarts` で受ける
- ⚠ 増減があるだけなら 0 で終わる（失敗ではなく、確かめる対象）
- ⚠ 稼働中の ID は手元のリポジトリの `tmp/cache/deploy-sources-before.txt` に控える（中身はソース ID だけ・`tmp/cache/` は git の無視対象）。4. の `verify.sh` がこれと比べて増減を出す

🔴 **pull の後・再起動の前に実行する。**再起動で走るのは pull した後のコードなので、定義も同じコードで読む（新しい版で増えたソース種別の定義や、新しい版の検査で倒れる定義は、古いコードからは見えない）。⚠ **DB を読む CLI（`source status` など）は使っていない** — この時点のスキーマは古く、マイグレーションが要る版では落ちる（下の注意の「DB を読む CLI の順序は…」）。

⚠ **この確認は手早く済ませる。**pull 済み・再起動前の間は、ディスクのコードと動いているコードが食い違っている。この段を挟んだぶん、その時間が延びている。

## 3. 再起動

```sh
ssh oscura 'sudo systemctl restart tomato-shrieker'
```

## 4. 確認

```sh
.claude/skills/deploy/scripts/verify.sh
```

読むだけ。先頭コミットと版・`ActiveState` / `NRestarts`・`/healthz`・再起動の前からのソースの増減（控えの時刻つき）・ソースの内訳（success 以外と silent / undelivered の一覧）・いまの常駐が出したログのうち `redirect refused` / `process identity` / `event dropped` の件数と、今日のログ全体の `not started`（起動に失敗したプロセスは別の番号なので絞らない）の件数を出す（どれも 0 が正常）。

- 版が上げたものになっていること、`ActiveEnterTimestamp` がいまの再起動であること、`NRestarts` が増えていないこと
- ⚠ **再起動の直後は、まだ一度も走っていないソースがある。**内訳は次の発火を待ってからもう一度読む。⚠ **宛先のリダイレクト拒否（`redirect refused`）は、そのソースが次に配信したときに初めて出る**＝配信の少ないソース（本番 59 件のうち 26 件は直近 8 日に配信が無い・2026-10-11 実測）は、日を置いてもう一度見る
- ログは `/var/log/tomato-shrieker.log`

## 切り戻し

前の版へ戻すとき。⚠ **本番に出す＝リリースするので、戻す先もタグを打った版にする。**

🔴🔴 **マイグレーションを含む版から戻すときは、コードを戻す前に DB を DOWN する (#1722)。**古い版のコードは自分より新しい `schema_info` を開けない。起動時の判定（`Sequel::Migrator.is_current?`）が `Missing migration version(s) needed to migrate down` で倒れ、**起動に失敗して再起動を繰り返す**。⚠ DOWN のファイルは新しい版にしか無いので、**新しい版のチェックアウトのまま**流す。

1. 止める: `ssh oscura 'sudo systemctl stop tomato-shrieker'`（⚠ 止めずに DOWN すると、再起動のたびに新しい版が UP し直す）
2. DB の控えを取り、マイグレーションを含むなら DOWN する。`<前の版>` はタグ（例: `v4.16.1`）

   ```sh
   ssh oscura 'sudo -H -u deploy bash -lc "
     set -e
     cd ~/repos/tomato-shrieker
     cp tmp/db/db.sqlite3 tmp/db/db.sqlite3.bak-\$(date +%Y%m%d%H%M)
     git fetch origin tag <前の版> --no-tags
     last=\$(git ls-tree --name-only <前の版> app/migration/ | tail -1 | xargs basename | cut -d_ -f1)
     echo \"DOWN to \$last\"
     bundle exec sequel -m app/migration -M \$((10#\$last)) sqlite://\$PWD/tmp/db/db.sqlite3"'
   ```

   - 戻す先と同じ本数なら何も起きない（マイグレーションを含まない版の切り戻しでもそのまま流してよい）
   - ⚠⚠ **列やテーブルを足すマイグレーションの DOWN はデータを落とす。**流す前に、新しい版のリリースノートの「切り戻し」の欄（[release スキル](../release/SKILL.md) の 5.）と、該当する `app/migration/` の `down` を読む。014 は索引だけなので落ちるものは無い
3. コードを戻す: `git reset --hard <前の版>`・`bundle install`・`bundle check`（`pull.sh` と同じく `sudo -H -u deploy bash -lc` の中で）。⚠ **`.ruby-version` が版で違う**ときは、前の版の Ruby が oscura に残っているかを先に確かめる。サテライト 3 本は本体と同じ Ruby で動くので、Ruby が戻るならサテライトも `RBENV_VERSION=<前の版の Ruby> bundle install` する
4. 起こす: `ssh oscura 'sudo systemctl start tomato-shrieker'` → 4. の `verify.sh`
5. 次のデプロイは 1. からそのまま流せる（`deploy` ブランチは main の祖先に戻っているので、`git pull origin main` は早送りになる）

## 注意

🔴 **`bundle install` は本体・サテライトとも毎回必ず実行する。**冪等なので無駄打ちのコストはほぼ無い。省くと以下で壊れる。

- **Ruby のマイナー更新**（例: 4.0.5 → 4.0.6）で gem ディレクトリが総入れ替えになる。本体だけ `bundle install` してサテライトを忘れると、**サテライトだけが `Bundler::GemNotFound` で全滅**する（2026-08-03 に実際に発生。`loquat` / `shooby-do-bop` / `dqdai-anniv` の 7 ソースが `timecop` 欠落で 24 時間エラー）
- ginseng-\* gem は `branch: main` 追いなので、`Gemfile.lock` が同じでも中身が動く

⚠ **サテライトの `.ruby-version` は当てにならない。**サテライトは自分の `.ruby-version` ではなく **本体と同じ Ruby で動く**（理由は [docs/CLAUDE.md](../../../docs/CLAUDE.md) の「コマンドを走らせるソース（CommandRunner）の子プロセス実行」）。`bundle install` も同じバージョンを明示して実行すること（`pull.sh` は `RBENV_VERSION=$RV`）。

⚠ `git pull` を引数なしで打つと `There is no tracking information for the current branch.` で止まる。itamae の `git` リソースが upstream 追跡を持たないローカルブランチ `deploy` に着地させるため。本体は必ず **`git pull origin main`** と書く（ブランチ名が実行ユーザー名と同じなのは偶然）。

⚠ `shooby-do-bop` の既定ブランチは `master`（他は `main`）。

⚠ **`sudo -iu deploy bash -lc "…"` は改行を潰す。**複数行のコマンドが 1 行に連結されて構文エラーになる。複数行で書くときは `pull.sh` と同じ `sudo -H -u deploy bash -lc "…"` にする（1 行なら `-iu` でも通る）。

⚠ `config/local.yaml` と `config/sources/` は gitignore 配下＝git では上がってこない。ソース定義の正本は本番の実体で、手元の `config/sources` は dev 用。

⚠ `rake migrate` は不要（起動時に自動適用される。[daemon.md の「起動時マイグレーション」](../../../docs/daemon.md#起動時マイグレーション) 参照）。

⚠ **DB を読む CLI の順序は「pull → 再起動 → CLI」で固定する。**マイグレーションを走らせるのは `SchedulerDaemon#start` だけで、`bin/shrieker` は `Sequel.connect` しかしない。再起動前に新テーブルを触るサブコマンド（`source ack` → `silence_ack`）を叩くと、Thor のエラーではなく生の `Sequel::DatabaseError: no such table` で落ちる。
