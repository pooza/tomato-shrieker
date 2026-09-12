# 監視 (Kuma 連携)

⚠ **`/healthz` `/status.json` `source_run_log` と監視設定の正本。**監視まわりを読む・触るときは必ずここを開く。

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
- 連続エラー回数が `/monitor/error_streak_threshold` 未満である
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
| `/monitor/error_streak_threshold` | `1` | `/healthz/source/:id` を 503 にする連続エラー回数 |
| `/monitor/sample_size` | `50` | 統計・streak の算出に使う直近 run 件数 |

ソース定義側で上書きできるキー:

| キー | 意味 |
|------|------|
| `/monitor/tolerance` | 実行遅延の猶予。文字列なら `'30m'` のような Rufus 形式、数値なら秒。既定は `/monitor/default_tolerance_seconds` |
| `/monitor/silence_tolerance` | 無配信の許容期間。**未指定ならサイレント不発を検知しない**（opt-in） |

`silence_tolerance` はソースの性格に合わせて宣言する。年単位で正常に静かなソースに短い値を置くと過検知になる。**過検知は監視の信頼を壊す**ので、観測された最大の無配信間隔を上回る側に丸める。

```yaml
# 週次で必ず何か出るはずのソース
monitor:
  tolerance: 30m
  silence_tolerance: 30d
```

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
