# リリース前検証手順

RC や正式版リリース前に、開発環境で各 Source / Shrieker が動くことを手動検証する手順。CI のテストスイートでは捕まえきれない統合上のリグレッション（外部 API・gem 連携・設定読込）を発見する目的で実施する。

実例: 4.0.0 RC1 → RC2 では、本手順により PieFed 投稿の常時 NameError を発見した（`PiefedShrieker#exec` の `config` 参照が `include Package` 外しの影響で未定義になっていた）。

## 前提

- ローカルに `bundle install` 済みで `bin/shrieker` が動くこと
- `config/local.yaml` に `crypt.password` を設定済み（Nostr nsec 暗号化用、任意の文字列でよい）
- Google News Cleaner (`http://kues:3000/clean` 等) に到達できること（GoogleNewsSource の検証時のみ）
- PieFed テストコミュニティ (`pf.korako.me/c/local_test`, community_id 82, user `tomato_test`) に投稿可能なアカウント情報

## テスト用ソースの配置

`config/sources/` は `.gitignore` で `*` 除外されているため、テスト用 YAML は commit されない。手元にだけ配置する。

下記テンプレートを `config/sources/test-*.yaml` として保存し、`bin/shrieker source list` で全 ID が認識されることを確認する。

### test-ical-schedule.yaml — IcalendarSource (cron + days)

```yaml
source:
  ical: https://calendar.google.com/calendar/ical/c_21d8cc4216f2385ba8eb2f04a61c1a29b3298c814882956d8635f98542423466%40group.calendar.google.com/public/basic.ics
  days: 7
schedule:
  cron: '4 0 * * *'
dest:
  tags:
    - test
```

### test-ical-remind.yaml — IcalendarSource (remind)

```yaml
source:
  ical: https://calendar.google.com/calendar/ical/c_b7c1e56a53f76253c22d0bbf0c95056f4d10753889ea91e917030dcb2a49c82e%40group.calendar.google.com/public/basic.ics
schedule:
  cron: '10 0 * * *'
  remind:
    enable: true
dest:
  sanitize: html
  tags:
    - test
```

### test-youtube-channel.yaml — YouTubeChannelSource (URL 指定)

```yaml
source:
  youtube:
    channel:
      url: https://www.youtube.com/channel/UCSsjL41NsyqSNNbanuI0htg
dest:
  tags:
    - test
```

### test-youtube-keyword.yaml — YouTubeChannelSource (ID + keyword フィルタ)

```yaml
source:
  youtube:
    channel:
      id: UCM4y31BLBY-E8TNOmy3zPeQ
  keyword: 'ダイの大冒険'
dest:
  tags:
    - test
```

### test-github.yaml — GitHubRepositorySource

```yaml
source:
  github:
    repos: pooza/tomato-shrieker
dest:
  tags:
    - test
```

### test-text.yaml — TextSource

```yaml
source:
  text: |
    これは tomato-shrieker 検証用のテストテキストです。
    https://github.com/pooza/tomato-shrieker
dest:
  tags:
    - test
```

### test-google-news-piefed.yaml — GoogleNewsSource + cleaner + PieFed

PieFed 投稿の経路を実投稿で検証するための唯一のソース。`dest.piefed` を持つ。

```yaml
source:
  news:
    phrase: プリキュア
    cleaner:
      url: http://kues:3000/clean
keep:
  years: 1
dest:
  piefed:
    host: pf.korako.me
    user_id: tomato_test
    password: <テストアカウントのパスワード>
    community_id: 82
  tags:
    - test
```

### test-nostr.yaml — Nostr スモークテスト

実投稿はせず、設定読込・nsec 復号・キーペア生成までを確認する。

1. 使い捨て nsec を生成: `bundle exec ruby -Iapp/lib -rtomato_shrieker -e 'p = Nostr::Keygen.new.generate_key_pair; puts p.private_key.to_bech32'`
2. 暗号化: `bundle exec bin/crypt.rb --text=<nsec>`
3. 出力された暗号文を YAML に貼る:

```yaml
source:
  text: |
    Nostr スモークテスト用テキスト。
dest:
  nostr:
    private_key: <暗号化された nsec>
  tags:
    - test
```

## 検証コマンド

### 1. 全ソース認識確認

```sh
bundle exec bin/shrieker source list
```

すべての `test-*` ID が出力されることを確認する。

### 2. dry-run (FeedSource 系・IcalendarSource)

`source fetch` は upstream を取得して summary を出すだけで、Shrieker（投稿先）は呼ばない。

```sh
for id in test-ical-schedule test-ical-remind test-youtube-channel test-youtube-keyword test-github test-google-news-piefed; do
  echo "===== $id ====="
  bundle exec bin/shrieker source fetch $id 2>&1 | head -20
done
```

各ソースで `entries:` が取得できていればパス。`test-google-news-piefed` の entry URL が Google News のリダイレクト URL ではなく実 publisher URL になっていれば cleaner 連携も動いている。

### 3. TextSource / Nostr のスモークテスト

`source fetch` は TextSource 系で `source does not support fetch` を返すのが正常（取得元なし）。Nostr 設定の正当性は別途下記スニペットで確認する:

```sh
bundle exec ruby -Iapp/lib -rtomato_shrieker -e '
include TomatoShrieker
Sequel.connect(Environment.dsn)
src = Source.create("test-nostr")
shr = src.nostr
puts "NostrShrieker initialized: #{shr.class}"
puts "npub: #{shr.instance_variable_get(:@keypair).public_key.to_bech32}"
'
```

`NostrShrieker initialized: TomatoShrieker::NostrShrieker` と npub が出ればパス（暗号化された nsec の復号が通った証拠）。

### 4. PieFed 実投稿テスト

PieFed のテストコミュニティに実際に投稿する。Shrieker の動作は dry-run できないため、これだけは実投稿が必要。

```sh
bundle exec bin/shrieker source clear test-google-news-piefed   # 過去の Entry を消す
bundle exec bin/shrieker source shriek test-google-news-piefed  # 最新 1 件を投稿
```

PieFed 側 (https://pf.korako.me/c/local_test) で投稿が増えていることを確認する。あるいは API で確認:

```sh
curl -sS "https://pf.korako.me/api/alpha/post/list?community_id=82&sort=New&limit=3" | jq '.posts[].post | {published, title, url}'
```

注: `bin/shrieker source shriek` は初回（DB に Entry 履歴なし）のみ「最新 1 件のみ投稿」、2 回目以降は新規 entry を全て投稿する。連投したくない場合は事前に `clear` する。

### 5. PieFed 認証単独テスト（Shriek 失敗時の切り分け用）

```sh
bundle exec ruby -Iapp/lib -rtomato_shrieker -e '
include TomatoShrieker
Sequel.connect(Environment.dsn)
src = Source.create("test-google-news-piefed")
shr = src.piefed
puts "JWT: #{shr.instance_variable_get(:@jwt) ? "present" : "absent"}"
'
```

JWT が `present` なら login 成功。`absent` なら認証情報が古い等の可能性。

## チェックリスト

- [ ] `source list` で全 test-* が出る
- [ ] FeedSource (matrix-* 等)・IcalendarSource・YouTubeChannelSource・GitHubRepositorySource・GoogleNewsSource の `fetch` が成功
- [ ] cleaner 経由 (test-google-news-piefed) で実 publisher URL が取れている
- [ ] Nostr スモークテストで NostrShrieker が初期化される (nsec 復号成功)
- [ ] PieFed テストコミュニティに実投稿が反映される

## 後始末

- テスト用 `config/sources/test-*.yaml` は手元に残してよい（次回再利用）。git-ignore されているので commit はされない
- 検証で蓄積された `tmp/db/db.sqlite3` の Entry レコードはそのまま残しても問題ないが、繰り返し検証する場合は `bin/shrieker source clear <id>` で消す

## 関連

- [v4-plan.md](v4-plan.md) — 4.0 系のリリース計画
- [CLAUDE.md](CLAUDE.md) — リリースフロー全体（本手順は「セキュリティレビュー前」ステップに相当）
