# デーモン管理

⚠ **scheduler daemon の起動・停止・reload と `bin/shrieker` の正本。**

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

⚠ **サテライトの `.ruby-version` は当てにならない。**scheduler_daemon の環境には `RBENV_VERSION` が入っており、それが子プロセスへそのまま継承される。つまりサテライトは自分の `.ruby-version` ではなく **本体と同じ Ruby で動く**（[CLAUDE.md の CommandSource の子プロセス実行](CLAUDE.md#commandsource-の子プロセス実行) 参照）。`bundle install` も同じバージョンを明示して実行すること。

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
