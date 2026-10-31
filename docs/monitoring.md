# 監視 (Kuma 連携)

⚠ **`/healthz` `/status.json` `source_run_log` と監視設定の正本。**監視まわりを読む・触るときは必ずここを開く。

scheduler_daemon と同一プロセス内に Puma 埋め込みの軽量 HTTP サーバを同居させ、Kuma 等の外形監視ツールから叩ける HTTP エンドポイントを提供する。UI は持たず、Kuma のダッシュボードが一次情報となる設計。

## エンドポイント

| パス | 用途 | 応答 |
|------|------|------|
| `/healthz` | 総合ヘルスチェック | 200 / 503 |
| `/healthz/source/:id` | ソース別ヘルスチェック | 200 / 503 / 404 |
| `/status.json` | 全体ステータス（人間/ダッシュボード向け） | 200 (JSON) |

### `/healthz` の判定

scheduler プロセス生存 + DB 接続 + Rufus ジョブが 1 件以上、すべて満たせば 200。いずれかが NG なら 503。

### `/healthz/source/:id` の判定

該当ソースが以下をすべて満たせば 200:

- 配信先が 1 つ以上ある (`dest_count > 0`)
- 1 度は走っている。**ただし足したばかりのソースは、初回の実行期限までは 200**（下の「まだ走っていないソース」）
- 最終実行から `grace_seconds` 以内に走っている (stale でない)
- 連続エラー回数が `error_streak_threshold` 未満である（ソース単位で上書き可・#1558）
- **直近の配信試行に取りこぼしが無い (undelivered でない)**
- **配信へ進む前に失ったエントリが残っていない (lost_entries でない・#1574)**
- `silence_tolerance` を超えて無配信が続いていない (silent でない)

#### 配信へ進む前に失ったエントリ (#1574)

`Entry.insert` は配信より先に走るので、その後（テンプレートの描画・添付の取り出しなど）で落ちたエントリは unique 制約で二度と取得されない。⚠⚠ **同じ run で他のエントリが 1 件でも届くと、run は `partial`・`attempted == delivered` になり、未達（`undelivered`）も連続エラー（`error_streak`）も立たない**＝ 4.14.0 までは、エントリを恒久的に失ったのに healthz 200・エラー率 0% だった。

- **判定**: 直近の「エントリ処理段に入った run」（run_log の `entry_stage` が true の行）が、**保存の後で落ちたエントリ（`shrieker_errors` の `source#entry`）**か、**エントリ処理の途中で run ごと落ちた記録（`source#exec`）**を 1 件でも持っていれば 503。⚠ 4.14.0 までに書かれた行は、段に入った error 行で内訳が空のものも数える（件数が分からないので `lost_count: unknown (run aborted)`）。本文に `lost_entries: true` / `lost_at` / `lost_count` が出る。`/status.json` は `lost_entries`、`source status` の `PROBLEMS` 列は `lost_entries`
- ⚠ **`/status.json` と 503 本文の `entry_stage` は別の問い。**あちらは「いま連続している失敗のどれかが段に入っていたか」（しきい値を 1 に倒す理由）で、ここで言う「直近の段に入った run」とは見ている行が違う。`entry_stage: false` と `lost_entries: true` は同時に出うる
- **未達と同じ重さ・同じ消し方。**失われたものは戻らないので、**次にエントリを処理した run が何も失わない**か、**`bin/shrieker source ack ID` で確認する**まで赤い。⚠ 新着の無い run（段に入らない）を挟んでも消えない。⚠ 確認が消すのはその run だけで、確認より後に失えばまた赤くなる
- ⚠ **`undelivered` とは別の見出し。**宛先は健全でも起きるので、混ぜると運用者は存在しない宛先障害を探しに行く。同じ run で両方起きれば両方出る（件数は別々）
- ⚠ 数えないもの: 段に入っていない run（エントリを 1 件も読めていない＝失うものが無い）・`entry_stage` が NULL の旧行（migration 013 より前）
- ⚠ **保存の前（解析）で落ちたエントリは数えない。**行が無いので次の run が拾い直す。`shrieker_errors` の種別で分けている: `source#fetch`＝保存の前（数えない）・`source#entry`＝保存の後（数える）・`source#exec`＝エントリ処理の途中で run ごと落ちた（1 件と数える）
- ⚠ **専用の列は無い。**件数は `shrieker_errors` のうち上の 2 種別（`source#entry` / `source#exec`）の合計
- **根拠行は prune から守る（`last_entry_stage_ids`・#1687）。**確認しないまま保持期間（`/monitor/retention_days`）を過ぎても緑に戻らない
- ⚠ **添付が付かない・タグが付かないは、ここには出ない。**`RemoteAttachment`（Mastodon / Misskey の直接経路）と PieFed のタグ付けは、失敗しても投稿を成功として数える。分かるのはログの warn `attachment dropped` / `tags not attached` だけ（Sentry にも出ない）
- ⚠ エラー率（`error_rate_24h`）は変えていない（`error` の run だけを数える）

#### 定義は在るが読めないソース (#1605)

判別キー（`source/feed` など）を打ち間違えた定義（unmatched）は、どのソースクラスにも一致しないので `Source.all` に現れない。⚠ **それでも reload は古いジョブを残す（#1572）ので、古い定義のまま走り続けている。**

- `/healthz/source/:id` は **503**（本文 `no source class matched (unmatched definition): <id>`）。⚠ 4.14.0 までは 404 `Unknown source` で、意図的な削除や URL の打ち間違いと区別が付かなかった。**404 は本当に定義が無いときだけ**
- `/status.json` には `{id, class: null, error}` の行が残る（4.14.0 までは行ごと消えた）。`source status` の `PROBLEMS` 列は `unmatched`
- ⚠ `disable: true` の定義は対象外（止めたのだから問題にしない＝ 404・行なし）

#### まだ走っていないソース (#1560)

run が 1 行も無いソースは、**初回の実行期限**までは 200（本文は `OK (awaiting first run, due by <期限>)`）、期限を過ぎても走っていなければ 503（`No run recorded yet` と `first_run_deadline:`）。

- **期限 ＝ 起点から見た初回の発火予定 ＋ `grace_seconds`。**`every: 30m` なら起点の 30 分後、`cron` なら起点の次に来る発火時刻（日次なら最大 1 日）
- 🔴 **起点は、daemon の中では scheduler がジョブを登録した時刻 (#1686)。**`source reload` で足した・変えたソースは reload の時刻、daemon を再起動すれば起動の時刻になる（定義が変わらなかったジョブは reload で張り直さないので、時刻も前のまま）
  - 🔴 **ジョブが無いソースは期限が無い＝すぐ 503**（本文に `not scheduled`）。reload で登録に失敗した新しいソース（`CommandSource` の `bundle install` 失敗など）が、ジョブの無いまま期限まで緑に見えていた（4.15.0〜4.17.x は日次 cron で最長約 26 時間）
  - 定義を置いてから reload までに cron の時刻が挟まっても、実際の初回より前に期限が来ない（4.17.x までは定義ファイルの更新時刻が起点で、`0 6 * * *` を 05:59 に置いて 06:01 に reload すると 22 時間赤かった）
- 🔴 **期限なしで緑にはしない。**登録しただけで一度も走っていないソースが緑のまま残ると、#1504 で塞いだ「壊れているのに緑」へ戻る
- ⚠ **CLI（`source status`）は scheduler を持たないので、定義ファイルの更新時刻（いまのディスク）を起点に答える。**daemon の起動の途中（登録を終える前）も同じ。ジョブの有無も見ないので、登録に失敗したソースは CLI では期限まで `awaiting_first_run` のまま＝ **healthz と食い違う**。登録の失敗は reload の結果行（`--wait`）・ログ・Sentry の `failed` で見る
- `/status.json` の `first_run_deadline` で期限が読める（1 度でも走ったら `null`）。CLI の `PROBLEMS` 列には目印 `awaiting_first_run` が出る（問題ではないので `--problems` には出ない）
- ⚠ `every` のソースは daemon の再起動で位相が変わる（初回は再起動の 1 周期後）。起点も再起動の時刻になるので、期限もそれに付いていく

#### 宛先の一部にだけ届かない (undelivered・#1504)

**宛先の一部にだけ配信できていない状態を検知する (#1504)。**直近の「配信を試みた run」(`attempted_count > 0`) で `delivered_count < attempted_count` なら 503。

🔴 **2026-06 の Matrix 配信停止 (#1455) がこの形だった。**matrix 系 3 ソースは `hooks` を 2 つ持ち、`hook[0]`（matrix-webhook）が毎回失敗する一方 `hook[1]`（モロヘイヤ）は成功していた。`delivered_count > 0` なので status は `partial`、`last_delivered_at` も前進し続け、**error_streak も silent も立たず監視は最後まで緑だった。**

⚠ **解除は「次に全宛先へ届いた run」だけ。no-op run では解除しない。**取りこぼしたエントリは再送されない（`Entry.insert` が配信より先に走り、`entry.tooted` 列は `migration/004` で削除済み）ため**永久に失われている**。新着が無いことは失敗の解消にならない。

🔴 **だからこそ `attempted_count` に載せてよいのは「宛先に触れた試行」だけ。**解除条件が「次に配信できるまで」である以上、過検知の代償は「翌日まで赤」ではなく**「次に新着が出るまで赤」**になる。本番の実測では 12 日間に 1 度も配信を試みていないソースが 40 件中 13 件あり、疎なソースなら数週間に及ぶ。

- **宛先を組み立てられなかった**（アクセサが例外を握って nil を返した）→ `DeliveryStats#record_unavailable` で **attempted に載せる**。届いていないのは事実なので未達で正しい
- **配信より手前で落ちた**（DB が混んだときの `Sequel::DatabaseError`、`create_template` の失敗等）→ `DeliveryStats#record_failure` で **attempted には載せない**。宛先は全部健全なのに「宛先に届いていない」と表示すると、運用者は存在しない宛先障害を探しに行く。`@errors` には積むので status は `error` / `partial` に倒れ、`error_streak` では捕まる。⚠ **保存の後で落ちたぶんは `lost_entries` が拾う（4.15.0・#1574）。**同じ run で他のエントリが届くと status は `partial` になり、`error_streak` では捕まらないため

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

🔴 **streak は `/monitor/retention_days` の cutoff より古い行で止まる (#1608)。**⚠⚠ prune は下の「prune から守る 5 系統」をソースごとに**無期限に残す**ので、**疎なソース**では retention 内の行が読む件数より少なく、**守られた古い行がそのまま末尾に並ぶ**。間にあった成功行は消えているため、これを止めないと**何か月も前の最初の run のエラーが直近のエラーと地続きに見え、実際には連続していない失敗で 503 が立つ**。⚠ 守られた行は `last_delivered_at` / `observed_since` の**根拠行**であって、**連続性の根拠ではない**。

🔴🔴 **ただし先頭行（直近の run）だけは cutoff を免除する (#1621)。**⚠⚠ **免除しないと、実行間隔が `retention_days` より長いソースが「失敗したまま緑」になる**。月次 cron × しきい値 1 × retention 14 日で、その月の唯一の run が error だと、**15 日目までは 503 なのに 16 日目に `executed_at < cutoff` へ落ちて streak が 0 になり、次の run までずっと 200 OK** になる。⚠ `next_run_at` は翌月なので `stale` も立たず、`silence_tolerance` は opt-in ＝ **誰も気づかない**。⚠ 免除してよいのは先頭行だけで、これは「直近の run の結果」そのもの＝連続性を仮定せずに数えられる。#1608 が消したかった水増しは**保護された古い行をまたいで数えること**なので、2 行目以降で cutoff が効けば目的は損なわれない。

**サイレント不発の判定 (#1470)** は `silence_tolerance` を宣言したソースだけが対象（opt-in）。`chikanan` のように年単位で正常に静かなソースがあるため、一律の既定値は置かない。

**値の決め方**: 観測した最大の無配信間隔の **2 倍以上**で丸める（`p95` ではなく `max`。過検知は監視の信頼を壊す）。⚠ run_log から根拠を取るときの罠が 2 つある。

- ⚠ **測れるのは `retention_days`（14 日）まで。**それより長い間隔は run_log からは見えない
- ⚠ **prune の保護行（最古の run など）を窓に混ぜると、偽の巨大な間隔が出る。**必ず `executed_at >= <今日 - retention_days>` で窓を切ってから測る

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

📌 **未達の判定の入口は `Source#undelivered?` の 1 つ (#1509)。**`/healthz/source/:id`・`/status.json`・`source status`・`source ack` のどれもこれを通る（直近の配信試行の行を選び、確認も見る）。`SourceRunLog#undelivered?` は「その行が未達か」だけを答える。

🔴 **`ack` は未達 (`undelivered`) にも効く (#1506)。**⚠ **消えるのは「確認したその試行」だけ**で、確認より後の試行で再び届かなければまた赤くなる（サイレント不発と同じ規則）。⚠⚠ **`silence_tolerance` が未設定のソースを確認すると、次に配信を試みるまで再警告されない**（宛先が死んだままでも、新着が来るまでは緑）。`ack` の出力がそう言う (#1567)。

⚠⚠ **「確定的な信号を運用者が消してよいのか」は判断した上でこうしている。**取りこぼしたエントリは**再送されないので、赤を放置しても失われたものは戻らない**。一方 **2026-09-05 の実測では 57 ソースのうち 17 件が 12 日間に配信試行ゼロ**で、逃げ道が無いと疎なソースは数週間 503 に貼り付く。**「いつも赤いモニター」は監視ごと信用されなくなる**ほうが害が大きい。

⚠ **`ack` はソースごとに 1 つの記録**（`silence_ack` テーブル）なので、**未達・取りこぼしには確認の時刻で効く**。📌 **沈黙の起点が動くのは、沈黙の警告が出ていたときか、ほかに警告が無いときだけ（#1680）**＝未達だけの確認で沈黙の警告を遅らせない。⚠ しきい値の無いソースで未達を確認すると、次の配信試行まで再警告は無い（期限は持たせない・ユーザー判断）。`bin/shrieker source ack` は**実際に効いた範囲だけを出力する**。

📌 **この仕組みがあるので `silence_tolerance` を保守的に丸める必要は無い。**偽陽性のコストが「設定を直す」から「1 回確認する」に下がる。

⚠ **確認済みのソースは `silent: false` になるが、それは健全だからではない。**`/status.json` の `acknowledged_at` で「なぜ緑なのか」を答えられるようにしてある。⚠ **4.14.0 までのキー名は `silence_acknowledged_at`（#1567 で改名）。**確認は未達（`undelivered`）にも効くので、`undelivered: false` の理由もこのキーで読む。503 本文の行も同じ名前。内部の名前（`SilenceAck` クラス・`silence_ack` テーブル）は据え置いている。

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
| `null` | run が 1 件も無い（まだ一度も走っていない）。`silent` は `false`（#1560 の初回の期限の領分） |

⚠ **初回 run でいきなり配信できたソースは `observed_since` と時刻が一致する**が、`delivery` が勝つ（同着は宣言順）。

### `/status.json` の中身

```json
{
  "scheduler": true,
  "database": true,
  "ruby": {"version": "4.0.9", "yjit_available": true, "yjit_enabled": true},
  "reload": {
    "count": 3,
    "action": "reload",
    "at": "2026-10-16T08:00:00+09:00",
    "result": {"added": [], "removed": [], "changed": ["matrix-news"], "failed": [], "unmatched": []},
    "error": null
  },
  "sources": [
    {
      "id": "matrix-news",
      "class": "TomatoShrieker::FeedSource",
      "schedule": {"type": "every", "value": "5m"},
      "grace_seconds": 7200,
      "source_defaults": {},
      "last_run_at": "2026-04-14T14:00:00+09:00",
      "first_run_deadline": null,
      "next_run_at": "2026-04-14T14:05:00+09:00",
      "last_status": "success",
      "last_error": null,
      "last_duration_ms": 423,
      "dest_count": 1,
      "last_attempted_count": 2,
      "last_delivered_count": 2,
      "last_attempted_at": "2026-04-14T14:00:01+09:00",
      "undelivered": false,
      "lost_entries": false,
      "last_delivered_at": "2026-04-14T14:00:01+09:00",
      "last_delivered_at_origin": "run_log",
      "error_streak": 0,
      "error_streak_threshold": 1,
      "entry_stage": false,
      "noop_streak": 0,
      "noop_since": null,
      "silence_tolerance_seconds": null,
      "silent": false,
      "silence_baseline": "2026-04-14T14:00:01+09:00",
      "silence_baseline_origin": "delivery",
      "acknowledged_at": null,
      "acknowledged_run_id": null,
      "acknowledged_reasons": null,
      "error_rate_24h": 0.0,
      "duration_ms": {"min": 120, "avg": 380, "max": 1200, "p95": 900},
      "shrieker_errors": {"TomatoShrieker::MastodonShrieker": 1},
      "digest": "3f2a…"
    }
  ]
}
```

Kuma からは見ない（人間が `curl | jq` する用、または外部ダッシュボードに食わせる用）。

`reload` は**ソース定義を読んだ結果** (#1529)。`count` は起動時の登録を含めて読んだ回数で、失敗しても進む。`action` はその回の種類（起動時の登録が `register`、HUP が `reload`。まだ一度も読んでいなければ `null`）。失敗なら `result` は `null`、`error` に例外のクラス名（メッセージは載せない）。`bin/shrieker source reload --wait` がこれを読む（[daemon.md](daemon.md)）。

`digest` は**いま scheduler に登録されている定義**のハッシュ (#1672)。`Scheduler.digest` で、reload が変更を見分けるのと同じもの。ディスク上の定義と比べれば、編集したまま reload していない定義（再起動で黙って有効になる）が分かる（deploy スキルの `pending_sources.sh`）。一度も登録できていない新しいソースは `null`、読めない定義の行はキーごと無い。⚠ 変更した定義の reload が失敗した場合は古い digest が残る。⚠ CLI の `source status` は scheduler の外で動くので出さない。

`last_delivered_at_origin` は配信時刻の出どころ:

| 値 | 意味 |
|------|------|
| `run_log` | 保持期間内の実配信記録 |
| `fallback` | ソース種別ごとの永続データ由来。`FeedSource` 系は `entry` テーブルの最新 `published` |
| `null` | どちらからも取れない（＝配信実績を確認できない） |

`noop_since` は**いま続いている空振りの起点** (#1498)。最後に実際に配信できた run の時刻で、一度も配信していなければ観測開始（＝少なくともそこから）。空振りしていなければ `null`。⚠ `noop_streak` は直近 `sample_size` 件しか数えないので **50 で頭打ち**になる（`every: 5m` なら約 4 時間で飽和）。どれだけ長く空振りしているかは `noop_since` で読む。`/healthz/source/:id` の沈黙の 503 本文にも出す。

⚠ **`fallback` は人間が読むための参考値で、`silent?` は使わない (#1483)。**`entry.published` は上流フィードが自称する公開時刻で、`Entry` の行は配信の成否と無関係に INSERT される。**配信できていなくても上流に新着があるかぎり前進し続ける**ので、判定に使うと「配信していないのに健全」になる（Google News の pubDate が信用できない件と同根）。一次情報は `run_log` 側。

⚠ **prune はソースごとに 5 行を守る。**

| 守る行 | 理由 |
|------|------|
| 最後に配信できた run | 刈ると沈黙が `retention_days` を超えた瞬間に `last_delivered_at` が nil に化け、**沈黙が長引くほど検知できなくなる** (#1470) |
| 最古の run | 未配信のソースは上の保護に引っかからない。刈ると `observed_since` が常に `retention_days` 前に張り付き、それより長い `silence_tolerance` が永久に成立しない (#1483) |
| 最後に配信を試みた run | 刈ると未達で赤くなったソースが `retention_days` の経過だけで黙って緑に戻る。**次に配信できたときだけ解除する**という仕様が壊れる (#1504) |
| 直近のエントリ処理段の run | 刈ると、新着 1 件だけが落ちた run（配信の試行が 0）の `lost_entries` が保持期間の経過だけで緑に戻る (#1687) |
| 直近の run | 🔴🔴 streak は**先頭行だけ cutoff を免除する**ので、**先頭行が本当に最新の run でなければならない** (#1621)。⚠⚠ no-op success（新着が無く配信ゼロで完走した run）は上の 4 系統のどれにも掛からないため、これが無いと**疎なソースで「最新の成功 run だけ刈られ、最古行として守られた古い error が先頭に来る」**＝ **一度直ったソースが永久に赤いまま**になる |

`silence_tolerance` に `retention_days` より大きい値を書けるのはこの保護があるため。

**腐った設定と「正常に静か」の見分け方**は `silent` と `last_delivered_at` を突き合わせる。`last_status` は「run が完走した」を意味するだけで「配信した」ではないので、これだけを見てはいけない。

## `Bad response 3xx` の読み方

4.14.0 から、宛先（Webhook / LINE / PieFed / Mastodon / Misskey）はリダイレクトを追わない。宛先が 3xx を返すと、run_log・`/healthz/source/:id`・`/status.json`・Sentry には **`Ginseng::GatewayError: Bad response 301`**（302 / 307 / 308 も同じ形）としか出ない。再送はしない。

- **転送先はログにだけ出る。**同じ時刻の `{"error":"redirect refused",…,"location":"…"}` の行を見る。⚠ この行に `source:` は無いので、直後の `{"source":…,"shrieker":…,"error":…}` の行と時刻で結ぶ
- **直し方は、宛先の URL を `location` の示す最終オリジン（`https://`）へ書き換える**こと。`bin/shrieker source validate` は `http://` の宛先を WARN する
- 監視は効く: `attempted > 0 / delivered = 0` の error になるので、`errored` と `undelivered` で `/healthz/source/:id` が 503 になる
- ⚠ フィードの取得（FeedSource / IcalendarSource など）は従来どおりリダイレクトを追う

## CLI で横断して問い合わせる (#1561)

`/status.json` を全部舐めなくても、本番で次のように引ける（⚠ 本番では `sudo -iu deploy bash -lc "cd ~/repos/tomato-shrieker && bin/shrieker ..."`）。HTTP を経由せずプロセス内で DB を読むので、**daemon が止まっていても答えられる**。

```sh
bin/shrieker source status                    # 1 ソース 1 行（無効ソースは --all で出る）
bin/shrieker source status --problems         # /healthz/source/:id が 503 になるものだけ（あれば終了コード 1）
bin/shrieker source status --sort=error_rate  # error_rate / last_delivered / streak
bin/shrieker source status --json             # /status.json の sources[] と同じキー
bin/shrieker source collisions --hours=24     # 同じ秒に発火したソースの群
```

🔴 **組み立ても判定も Web と同じもの（`SourceStatus`）を通す。**`--json` の行は `/status.json` と、`--problems` の判定は `/healthz/source/:id` と一致する（テストで突き合わせている）。⚠ CLI 用に計算を書き直さない — 2 つの出口が同名フィールドで違う数字を出す不具合は `last_attempted_count`（4.8.0）としきい値の実効値（#1558）で 2 回直している。

`PROBLEMS` 列の値は `stale` / `errored` / `silent` / `undelivered` / `lost_entries`（`/healthz/source/:id` の判定材料）と、`no_dest` / `no_run` / `unmatched`（判定材料を見るまでもなく 503。`unmatched` は #1605）。`disabled` と `awaiting_first_run`（#1560）は問題ではなく目印で、**`--problems` には出ない**（どちらも healthz は 200）。

⚠ **CLI だけが出す値が 1 つある: `build_failed`**（そのソースの状態を組み立てる途中で例外が出た）。理由は表の後に `<id>: <例外>` の形で **stderr** へ出す（`--json` では行の `error` キー）。⚠ 空の DB や migration 前の DB に向けると全行がこれになる（`no such table: source_run_log`）。⚠⚠ **healthz と食い違いうる。**`/healthz/source/:id` は判定材料しか読まないので、表示用の集計（`error_rate` など）だけが落ちる場合は healthz が 200 のまま、CLI は `build_failed` を出す＝ **`--problems` は「healthz が 503 のもの」＋「CLI が状態を組み立てられなかったもの」**。

⚠ **CLI はディスク上の定義で答える。**daemon は読み込み済みの定義で走っているので、`source edit` / `disable` / `enable` の後・`source reload` の前に打つと、`/healthz/source/:id` と食い違う。

🔴 **`--problems` は、該当が 1 件でもあれば終了コード 1 で終わる**（`--json` を付けても同じ。`source validate` が NG で非 0 を返すのと揃えた。stderr に `N source(s) have problems.` を 1 行出す）。該当が無ければ 0＝ `bin/shrieker source status --problems || 通知` の形で使える。⚠ **`--problems` を付けない一覧は、赤いソースがあっても 0**（一覧を出しただけ）。⚠ `--sort` に知らないキー・`collisions --hours` に 0 以下を渡したときも非 0。

⚠ **`--json` は `problems` / `disabled` を持たない**（`/status.json` の `sources[]` と同じキーという約束どおり）。`--all --json` は無効ソースを印なしで混ぜるので、無効かどうかは表（`PROBLEMS` 列の `disabled`）で見る。

⚠ `collisions` は**定義ではなく run_log の実績**から見る。`every` の位相は起動時刻で決まるので、定義を突き合わせても同時発火は分からない。

## 設定

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

### `error_streak_threshold` の上書き (#1558)

⚠ **外部の安定度はソースの性質。**YouTube の `feeds/videos.xml` は**チャンネルが生きていても 24h で 7〜10% 失敗する**一方、GitHub の `releases.atom` は 0%。グローバル値だけだと、上げれば安定したソースの検知が鈍り、下げようもない。

🔴 **グローバル値だけだった間、この調整は Uptime Kuma の `maxretries` へ漏れ出していた。**⚠ **ソース定義を読んでも「何回で赤くなるか」が分からない**状態になるので、道具側に置く。

```yaml
# 取得元が間欠的に失敗するソース
monitor:
  error_streak_threshold: 4
  silence_tolerance: 90d
```

⚠⚠ **緩めても「本当に死んだら赤くなる」ことは変えない。**`cron: '0,15,30,45 * * * *'` なら 4 連続＝**1 時間で赤**。エラー率 7.3% なら 4 連続失敗の確率は 0.003% で、偽陽性はほぼ消える。

⚠ **読む行数（`streak_window`）も一緒に広がる。**`sample_size` より大きいしきい値を書いても窓が足りず到達し得ない、という穴を作らないため。⚠ **`/status.json` の `error_streak` も同じ窓で数える。**片方だけだと `error_streak: 50 / 100` という自己矛盾した数字が出る。

🔴🔴 **しきい値の回数ぶんの run が `/monitor/retention_days` の窓に収まらなければならない。**`error_streak` が数えるのは `source_run_log` の行で、その行は prune で消える。⚠⚠ **疎なソースでしきい値を上げると、必要な本数の error 行が揃う前に古い行が消えるので、どれだけ連続で失敗しても 503 にならない。**⚠ `stale` も助けにならない（run 自体は走っていて `executed_at` は前に進む）。

```
月次 cron（0 0 1 * *）× しきい値 3 → 14 日の窓に最大 1 回 → 永久に緑
平日 cron（0 0 * * 1-5）× しきい値 12 → 14 日の窓に最大 10 回 → 永久に緑
月初 2 日（0 0 1,2 * *）× しきい値 2 → 1 日と 2 日が同じ窓に入る → 届く
15 分間隔 × しきい値 8 → 14 日の窓に 1344 回 → 問題なし
```

⚠ **「しきい値 × 実行間隔」で見積もらない。**不均一な cron（平日限定・月初だけ）で外れる。判定は**回数**で、**窓をどこに置いても最大いくつ入るか**で見る（#1587 / #1594）。

⚠ **`bin/shrieker source validate` が WARN で指摘する。**NG にしないのは、妥当かどうかの判定に実行間隔が要り、**スキーマでは表現できない**ため。⚠ 1 つの定義が複数のクラスにマッチする場合は各インスタンスの最大の和で見る。密で長周期の cron（`* * * 1-11 *` など）は走査の上限で判定を諦め、警告しない

### 🔴 緩められるのは「エントリを 1 件も失っていない失敗」だけ

⚠⚠ **しきい値をいくつにしても、エントリを失いうる段まで進んでから落ちた失敗は 1 回で 503 になる。**

```
取得そのものが失敗・パース失敗（entry_stage: false）→ しきい値が効く
エントリの行を作った後に失敗（entry_stage: true）   → 1 回で赤
```

⚠ 「読んだかどうか」ではなく「**取り返せるかどうか**」で分ける。FeedSource のパース失敗は `Entry.insert` の手前なので行が無く、次の run で読み直される＝緩和が効いてよい側（#1622）。

🔴 **これが無いとエントリが恒久的に失われる。**`Entry.insert` は配信より先に走るので、`create_record` / `create_template` / `enclosures` / `Entry#shriek` 以降で落ちた run のエントリは **unique 制約で二度と取得されない**。しかもその失敗は `record_failure` 経由で `attempted_count` に載らないため、⚠⚠ **`undelivered` も `stale` も `silent` も立たず、`error_streak` が唯一のゲート**になっている（#1473 / `DeliveryStats#record_failure` のコメント）。

🔴🔴 **段は `source_run_log.entry_stage` が直接持つ (#1586)。**⚠⚠ 4.9.0 までは **`shrieker_errors` が空であること**を「取得段の失敗」の**代理**にしていたが、**その代理が成立するのは FeedSource だけだった**。`CommandSource#exec` / `IcalendarSource#exec` は `create_template` で落ちると `@delivery_stats` が空のまま `exec_with_run_log` の rescue に入るので、**`shrieker_errors` が空の error 行**になる ＝ **エントリ処理段の失敗が「取得段の失敗」と誤読され、緩めたしきい値がそのまま残っていた**。代理をやめて事実を書く、という差分。

- 段を立てるのは **`DeliveryStats#enter_entry_stage!`**。各 Source が**エントリの一覧を取り出した直後**に 1 回だけ呼ぶ（取得の失敗はここへ到達しない／エントリ 0 件なら呼ばない）
- 🔴🔴 **`FeedSource` だけは「一覧を取り出した直後」ではなく `create_record` が配信対象の行を返した直後 (#1622)。**⚠⚠ 一覧（`targets`）は `ignore_entry?` で絞っただけの**生のフィード項目**で、**重複判定を通していない**。重複判定は `Entry.create` が `Sequel::UniqueConstraintViolation` を掴んで nil を返すところで初めて起きるので、一覧の時点で立てると**既知エントリしか無い run（＝平常時のほぼ全 run）でも `entry_stage: true`** になる。⚠ **失うものが 1 件も無いのに `error_streak_threshold` が 28 → 1 に潰れ、一過性の失敗 1 回で 503** になる
- ⚠⚠ **`Entry.create` が `Entry.insert` を通した後に落ちた場合も段を立てる (#1622)。**行は残るのでそのエントリは次の run で `Sequel::UniqueConstraintViolation` に化けて**二度と配信されない**。`FeedSource#fetch` の rescue は段を立てる手前なので、ここで立てないと**恒久的な取りこぼしが「取得段の失敗」＝緩和が効く側**に分類される。⚠ insert より手前（パース失敗）で落ちたら立てない ＝ **失うものが無い**
- ⚠⚠ **`CommandSource` は非ゼロ終了でもエントリを失っていることがある。**`raise command.stderr unless command.status.zero?` までを取得段としているが、**子プロセスが落ちる前にキャッシュを進めている**ことがある（`precure-reserve` は `-n`（保存しない）が無いので `loquat reserves` が `tmp/cache/reserves-*.json` を更新する。`dqdai-reserve` には `-n` がある）。この形で落ちるとエントリは失われるのに `entry_stage: false` ＝ **緩和が効く側**に分類される。✅ 両者とも `error_streak_threshold` が 1 なので今は無害だが、**CommandSource でしきい値を緩めるときはこれを踏まえること**
- ⚠ `TextSource` は立てない。本文は設定の固定文字列で、落ちても次の run が同じものを流す
- ⚠⚠ **migration 013 より前の行は `entry_stage` が NULL。**NULL の行だけ従来の代理へ倒す。**「NULL ＝ エントリ処理段」にするとデプロイ直後に緩和を掛けているソースが一斉 503** になる（migration 010 の backfill と同じ型）
- 📌 **503 本文に `entry_stage:` が出る。**しきい値を 28 に緩めていても `error_streak: 1 / 1` になる理由がそこで読める

⚠ **`/status.json` の `error_streak_threshold` は実効値。**1 に倒されているときは `1` が出る（宣言値ではない）。**倒された理由は同じ行の `entry_stage: true` で読める (#1624)。**⚠ 503 本文の `entry_stage:` と同じ値（同じ窓の run を見る）で、503 になる前（`error_streak: 0`）でも出る。

⚠ **opt-in なので「書き忘れ」と「意図的に検知しない」が設定上は区別できない。**`bin/shrieker source validate` は監視対象なのに `silence_tolerance` が無いソースを `WARN` として出す（スキーマ上は妥当なので `NG` にはせず、終了コードも倒さない）。年単位で静かなソースは意図的に未設定のままでよい。

## 実行ログテーブル `source_run_log`

各 source の Rufus ジョブが発火するたびに INSERT される（`migration/009`, `migration/010`）。`/status.json` の集計用に、`attempted_count > 0` と `entry_stage = 1` の行だけを持つ部分索引が 2 本ある（`migration/014`・#1472・起動時に自動で当たる）:

- `source_id`, `executed_at`, `status` (`success` | `partial` | `error`), `error_message`, `duration_ms`
- `attempted_count` / `delivered_count` — その run で配信を試みた件数 / 実際に配信できた件数
- `entry_stage` — エントリ処理段まで進んでいた run か（`migration/013`・#1586）。⚠ 旧行は NULL
  - ⚠ **4.12.0 で FeedSource の意味が狭まった (#1622)。**「**配信対象の**新しいエントリの行を作った run（insert 後の失敗を含む）」だけが true。⚠ insert はしたが意図して流さない行（まだ touch していない／`feed.time` より古い／`keep_years` の外）は `create_record` が nil を返すので立たない＝失うものが無い。⚠⚠ **4.11.0 で書かれた行は既知エントリしか無い run でも true**（本番 14 日で約 3 万行）なので、**デプロイ前後で集計が不連続**になる
- `shrieker_errors` — shrieker (投稿先) 別のエラー件数を JSON で保持（例: `{"MastodonShrieker":2}`）。エラーが無ければ `NULL`
  - ⚠ **shrieker クラス名以外の値も入る。**宛先に一度も触れていない失敗はここへ **`UnavailableDest`**（設定はあるが Shrieker を組み立てられなかった宛先・#1504）や **`source#fetch`**（配信手前でエントリが落ちた・#1473 / #1485）として積まれる。**「どの宛先が失敗したか」と「どの処理段階が失敗したか」が同じ Hash に混在する**ので、集計を読むときは区別すること
  - 🔴 **4.15.0 で種別が 3 つになった (#1574)。**`source#fetch`＝保存の**前**（解析）で落ちたエントリ（次の run が拾い直す）／`source#entry`＝保存の**後**で落ちたエントリ（二度と取得されない）／`source#exec`＝エントリ処理の途中で run ごと落ちた（件数は不明なので 1）。⚠⚠ **4.14.0 までの `source#fetch` は保存の前後を区別していない。**run ごと落ちた error 行は、4.14.0 までは内訳が空（`NULL`）だった
  - 🔴 **古い行には `TomatoShrieker::FeedSource#fetch` のような旧キーが残っている。**#1485 でクラス名依存をやめて `source#fetch` に固定したが、それ以前の行はそのまま
- 古いレコードは Rufus ジョブで毎日 prune（`/monitor/retention_days`）
  - ⚠ 保護行（上の「prune はソースごとに 4 行を守る」）は残るが、**retention を過ぎると `error_message` は消える (#1511)**。⚠ そのため**実行間隔が retention より長いソースが error のまま 503 を立て続けると、15 日目以降の 503 本文には `error:` 行が出ない (#1621)**。原文は Sentry かログに残る。⚠⚠ **ただし宛先を組み立てられなかった失敗（`UnavailableDest`）は Sentry へ送らず `logger.error` だけ**で、ログは 7 世代でローテーションされる＝**retention を過ぎると原文はどこにも残らない**

計上は `Source#shriek` の各 shrieker 呼び出し単位で行い、`DeliveryStats` が Mutex 越しに集約する（`IcalendarSource#exec` は `Parallel.each` で並列配信するため）。

### run の status は `delivered_count` で決まる (#1482)

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

## Kuma の登録例

```
HTTP(s) Monitor:
  Name: tomato-shrieker
  URL: http://<host>:4567/healthz
  Interval: 60s
  Accepted Status Codes: 200-299
```

ソース別に追跡したい場合は `http://<host>:4567/healthz/source/<source-id>` を別モニターとして追加する。

## 運用: 監視ホストから tomato-shrieker への到達経路

`/monitor/bind` のデフォルトは `127.0.0.1` で、外向けには公開されない。監視ホスト（Kuma 等）から `/healthz` を叩く経路（VPN・SSH トンネル・同居・ファイアウォールでの IP 制限）の選び方は、利用者向けに Wiki「監視」にある。

本番は `local.yaml` の `/monitor/bind` を `0.0.0.0` にし、ホストのファイアウォールで 4567 を監視ホストにだけ開けている（構成管理は chubo2・#1531 → chubo2#200）。どの OS でも上の代替のどれかで届くので、**監視機能の有無で OS サポートの判断を変える必要はない**。

## 本番のログと値を読むときの罠

- **`next_run_at` は「直近の run ＋ 周期」で計算する。**`every` のソースは位相が起動時刻で決まるので、**再起動の直後の `next_run_at` は当てにならない**（初回は再起動の 1 周期後に来る）。一度も走っていないソースでは `null`
- **ログは日次でローテートされる（本番は 00 時台）。**深夜をまたぐ集計や「今日のエラー 0」の判断では、ローテート済みの `.log.1.gz` も `zgrep` で含める。午前に今日のファイルだけを見ると、前日の夜のぶんを落とす
- **ログの `"status":0` は、`"command"` キーと同居していればコマンドの終了コード（成功）。**HTTP の status ではない
- **`source shriek` は run_log を書かない。**手で流し直しても `/status.json` と個別 healthz の 503 は次の定時実行まで消えない。成否は HTTP のログ（`"method":"POST"` と `status`）で数える
