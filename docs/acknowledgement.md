# サイレント不発と確認 (ack)

⚠ **沈黙の判定（`silence_tolerance`）と、運用者の確認（`bin/shrieker source ack`）の正本。**[monitoring.md](monitoring.md) から分けた（#1772）。`/healthz/source/:id` の判定の全体・未達（`undelivered`）・取りこぼし（`lost_entries`）・`error_streak` の数え方・`/status.json` の中身は monitoring.md にある。

## サイレント不発の判定

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

⚠ **`ack` はソースごとに 1 つの記録**（`silence_ack` テーブル）なので、**未達・取りこぼしには確認の時刻で効く**。📌 **沈黙の起点が動くのは、沈黙の警告が出ているか判定不能（`silent` が `null`）のときだけ（#1680）**＝未達だけの確認で沈黙の警告を遅らせない。⚠ **警告が 1 つも無ければ何も記録しない**（打ち直しで起点と記録を動かさない。静かになると分かっているソースに先回りはできない）。⚠ しきい値の無いソースで未達を確認すると、次の配信試行まで再警告は無い（期限は持たせない・ユーザー判断）。`bin/shrieker source ack` は**実際に効いた範囲だけを出力する**。

📌 **この仕組みがあるので `silence_tolerance` を保守的に丸める必要は無い。**偽陽性のコストが「設定を直す」から「1 回確認する」に下がる。

⚠ **確認済みのソースは `silent: false` になるが、それは健全だからではない。**`/status.json` の `acknowledged_at` で「なぜ緑なのか」を答えられるようにしてある。⚠ **4.14.0 までのキー名は `silence_acknowledged_at`（#1567 で改名）。**確認は未達（`undelivered`）にも効くので、`undelivered: false` の理由もこのキーで読む。何を確認したかは `acknowledged_reasons`、沈黙の判定が確認に基づくかは `silence_baseline_origin` で読む。503 本文の行も同じ名前。内部の名前（`SilenceAck` クラス・`silence_ack` テーブル）は据え置いている。

⚠ **上の式の `silence_acknowledged_at` は `/status.json` に出ない (#1770)。**効いているときは `silence_baseline_origin: acknowledgement` で、その値が `silence_baseline` に出る（配信が追い越せば判定に関わらないので出さない）。⚠ `acknowledged_at` とは別物＝未達・取りこぼしだけの確認では動かない（#1680）。

⚠ **`acknowledged_reasons` が `null` なのは、4.19.0（migration 015）より前の確認**＝何を確認したかの記録が無い。`[]` とは別 (#1770)。⚠ **`acknowledged_run_id` は 1 つだけ**で、未達と取りこぼしが別の run にあると未達の run を指す（取りこぼし → error の順に次点）。どちらの警告も確認の時刻で解けるので赤緑には影響しない (#1770・実測済み)。

ソースの状況ごとの使い分け:

| 状況 | 対処 |
|------|------|
| 一時的に静か（たまたま 1 か月新着が無かった） | `bin/shrieker source ack ID` |
| 一時的な失敗で error（原因は分かっている） | `bin/shrieker source ack ID`（上流の復旧を待つなら `--until`・下の「error の確認」） |
| 投稿が恒久的に終了した | `bin/shrieker source disable ID`（＋ `source reload`） |
| 年単位で正常に静か（`chikanan` 等） | `silence_tolerance` を設定しない |

⚠ **`disable` にしたソースは監視対象外になり、`/healthz/source/:id` は `OK (disabled)` の 200 を返す (#1503)。**「意図的に止めた」と「壊れている」を同じ 503 で表さない。

⚠ **判定に使うのは run_log 由来の実配信だけで、`fallback` は見ない (#1483)。**[monitoring.md](monitoring.md) の `/status.json` の `last_delivered_at` の節のとおり、`fallback` は配信の成否と無関係に前進するため、これを信じると配信できていなくても `silent?` が永久に false になる。

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

## error の確認（4.20.0・#1749）

🔴 **`ack` は error（`error_streak` がしきい値に届いた状態）にも効く。**日次のソースが一時的な失敗で 1 回落ちると、次の定期実行まで丸 1 日赤いままになるため。⚠ **緑に戻すのは周期どおりの実行だけ、という判断は変えていない**: run_log には触らず（`error_streak` の数字もそのまま）、`/healthz/source/:id` の判定だけを抑える。

| 書き方 | 効く範囲 |
| --- | --- |
| `bin/shrieker source ack ID` | **確認した run まで。**次の定期実行がまた error なら赤に戻る（確認より後に終わった error の run は了解していない） |
| `bin/shrieker source ack ID --until 2026-11-14` | **期限まで。**その間の error でも緑。⚠ **期限の前に成功したら、その時点で解除する**（次の失敗はすぐ赤）。期限を過ぎたら、その時点の結果で判定し直す（確認した run のままでも赤） |

- ⚠ **期限の無い「ずっと緑」は作らない（ユーザー判断）。**`--until` は未来の時刻だけを受け、error の警告が出ていないソースには使えない（先回りの確認はしない）。🔴 **35 日先まで**（月次のソースでも次の実行まで届く長さ・#1785・ユーザー判断）。⚠ **書き方は `2026-12-01`（その日の 0:00）と `2026-12-01T12:00` だけ**（#1785）。`Time.parse` は `12` を今月 12 日、`2026-02-30` を 3/2 と読むので使わない。読み戻して一致しないもの（2/30 など）も弾く。出力に実際の時刻を出す
- 📌 **使いどころ**: `schedule.retry`（#1585）のやり直しも使い切ったとき（期限なし）と、原因が分かっていて上流の復旧を何日も待つとき・週次や月次のソース（`--until`）
- ⚠ **`--until` が抑えるのは error だけ。**その間の run が宛先で落ちれば未達（`undelivered`）で赤くなる（未達・取りこぼしは run ごとの確認のまま）
- ⚠ **`/status.json` の `error_acknowledged_at` / `_until` は記録で、いま効いているかではない。**次の error で赤に戻っても・期限が過ぎても値は残る（成功で消える）。📌 **いま抑えているかは `error_acknowledged`（真偽値）で読む**（4.21.0・#1785・判定は healthz と同じ）。`source status` の `PROBLEMS` 列には目印 `error_acknowledged` が出る（問題ではないので `--problems` には出ない）
- ⚠ **`acknowledged_reasons` の `errored` は「成功で解除」の後も残る**（何を確認したかの履歴・ほかの理由と同じ扱い・#1785 のユーザー判断）
- **緑でも本文で分かる。**`/healthz/source/:id` は `OK (error acknowledged until …)` / `OK (error acknowledged, re-evaluated at <次の定期実行>)` を返す（`schedule.retry` のあるソースは ` or at the next retry` が続く＝やり直しも次の run になる）。ほかの理由で赤いときは 503 の本文に同じ行が出る。`/status.json` は `error_acknowledged_at` / `error_acknowledged_until`、`acknowledged_reasons` に `errored`
- ⚠ **「成功で解除」は記録で持つ。**error で終わらなかった run（`success` / `partial`）を記録した時点で、error の確認を消す（`SilenceAck.clear_error`）。⚠ 判定のたびに run_log から探す形にすると、保持期間の掃除で成功の行が消えたとき確認が復活する（#1779 の Codex P2）。📌 **`source ack` は警告の読みと記録の書きを 1 つのトランザクションにする**（SQLite の `immediate`・#1785）＝確認の直前に記録された成功を見落とさない。🔴 **run の記録（`SourceRunLog.record`）の側は囲まない**（4.21.0 リリース前レビューの赤）。daemon の並列の run どうしが書き込みの錠を取り合い、GVL を握った待ちで詰まって run_log の行が欠ける。ack の側だけで「成功で解除」は守れる（作成の後に ack が来れば成功を読む・ack の後なら解除が効く）
