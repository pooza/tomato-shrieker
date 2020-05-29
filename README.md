# tomato-toot

![test](https://github.com/pooza/tomato-toot/workflows/test/badge.svg)

ボット作成支援ツール。詳細は[wiki](https://github.com/pooza/tomato-toot/wiki)にて。

## tomato-tootにできること

### 投稿できるテキスト

- 定型文
- RSS/Atomフィードの新着エントリー
- コマンドの実行結果（標準出力）

### 投稿できるタイミング

- 定期的に（デフォルトは5分ごと）
- 指定時刻
- cron形式の指定

### 投稿先

- Mastodon
- Slack互換webhookをもつサービス（拙作[モロヘイヤ](https://github.com/pooza/mulukhiya-toot-proxy)を含む）

## 由来

- forsquareのチェックインを自動投稿する用途が最初でした。プリキュア関連のニュースボットのエンジンとして利用を始めたのがその次です。
- いずれも、Atom/RSSフィードからMastodonへ投稿（トゥート）を行う仕様でした。tomato-tootの名前は、その頃の名残です。（トマトに深い意味はない）

## 宣伝

- 以下の拙作ボットのパーツとして使われています。
  - [「東映アニメーション プリキュア公式」の新着情報ボット](https://precure.ml/@toei_bot)
  - [「ABC毎日放送 プリキュア公式」の新着情報ボット](https://precure.ml/@abc_bot)
  - [「プリキュアガーデン」の新着情報ボット](https://precure.ml/@garden_bot)
  - [「プリキュア公式YouTubeチャンネル」の新着情報ボット](https://precure.ml/@youtube_precure_bot)
  - [「シュビドゥビ☆スイーツタイム」の再生回数を淡々と喋るボット](https://mstdn.b-shock.org/@shooby_do_bop_bot)
  - [「レッツ・ラ・クッキン☆ショータイム」の再生回数ボット](https://mstdn.b-shock.org/@lets_la_bot)
  - [増子](https://precure.ml/@mikabot)
  - [非公式「宮本佳那子のこころをこめて」更新通知ボット](https://mstdn.b-shock.org/@kanako_blog_bot)
  - [ぷーざリリースボット](https://mstdn.b-shock.org/@release_bot)

- 中の人は普段、個人インスタンス「[美食丼](https://mstdn.b-shock.org/)」か、プリキュア専用インスタンス「[キュアスタ！](https://precure.ml/)」に居ます。（いずれもMastodon）
- プリキュアに興味ある人は、是非キュアスタ！に来てください。
