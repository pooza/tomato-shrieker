# test/fixtures

`rake test` を**外部へ 1 通も出さずに**走らせるための応答本文 (#1468)。

⚠ **手元の `config/sources/*.yaml` は実サービスを指している**（GitHub / YouTube /
Google カレンダー / google-news-rss-cleaner）。⚠⚠ `config/sources` は git 管理外で
**開発機ごとに中身が違う**ため、URL を列挙しても網羅できない。`TestCase` が
**種類ごとにパターンで**塞ぐ（`stub_default_feeds`）。

| ファイル | 由来 | 用途 |
| --- | --- | --- |
| `youtube.xml` | `youtube.com/feeds/videos.xml` の実応答を 2 entry に切ったもの | `Feedjira::Parser::AtomYoutube` の経路 |
| `github.atom` | `github.com/pooza/tomato-shrieker/releases.atom` を 2 entry に切ったもの | `Feedjira::Parser::Atom` の経路 |
| `google_news.rss` | google-news-rss-cleaner の実応答を 3 item に切ったもの | `Feedjira::Parser::RSS` の経路 |
| `calendar.ics` | 手書き | `IcalendarSource` の経路 |

## ⚠ `calendar.ics` の日付はプレースホルダ

`__START1__` などは `TestCase#stub_default_feeds` が**実行時に埋める**。

🔴 **固定日付にしてはいけない。**`test-ical-schedule.yaml` は `days: 7` で絞るので、
固定にすると**フィクスチャが古びた日から `entries` が恒久的に空になり、テストが
何も確かめなくなる**（しかも緑のまま）。

## 更新のしかた

実応答を取り直したいときは、対象 URL を `curl` して先頭の数 entry だけ残す。
⚠ **資格情報や個人情報が本文に混ざっていないか確認すること。**
