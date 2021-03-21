# tomato-shrieker

![release](https://img.shields.io/github/v/release/pooza/tomato-shrieker.svg)
![test](https://github.com/pooza/tomato-shrieker/workflows/test/badge.svg)

ボット作成支援ツール。詳細は[wiki](https://github.com/pooza/tomato-shrieker/wiki)にて。

## tomato-shriekerにできること

### 投稿できるテキスト

- 定型文
- RSS/Atomフィードの新着エントリー
- コマンドの実行結果（標準出力）

### 投稿できるタイミング

- 定期的に（デフォルトは5分ごと）
- 指定時刻
- cron形式の指定

### 投稿先

- [Mastodon](https://github.com/tootsuite/mastodon)
  - [Pleroma](https://git.pleroma.social/pleroma)等、互換APIをもつサービスを含む。
- [Misskey](https://github.com/syuilo/misskey)
- Slack Incoming Webhooks
  - Discord等、webhookに互換性をもつサービスを含む。
  - 拙作[モロヘイヤ](https://github.com/pooza/mulukhiya-toot-proxy)を含む。
- [Lemmy](https://github.com/LemmyNet/lemmy/)
- LINE

## 由来

- forsquareのチェックインを自動投稿する用途が最初でした。プリキュア関連のニュースボットのエンジンとして利用を始めたのがその次です。
- いずれも、Atom/RSSフィードからMastodonへ投稿（トゥート）を行う仕様でした。その為、この頃はtomato-tootという名前でした。

## 宣伝

- 以下のボットのパーツとして使われています。
  - [「東映アニメーション プリキュア公式」の新着情報ボット](https://precure.ml/@toei_bot)
  - [「ABC毎日放送 プリキュア公式」の新着情報ボット](https://precure.ml/@abc_bot)
  - [「プリキュアガーデン」の新着情報ボット](https://precure.ml/@garden_bot)
  - [「プリキュア公式YouTubeチャンネル」の新着情報ボット](https://precure.ml/@youtube_precure_bot)
  - [「シュビドゥビ☆スイーツタイム」の再生回数を淡々と喋るボット](https://mstdn.b-shock.org/@shooby_do_bop_bot)
  - [「レッツ・ラ・クッキン☆ショータイム」の再生回数ボット](https://mstdn.b-shock.org/@lets_la_bot)
  - [「エビバディ☆ヒーリングッデイ！」再生数ボット](https://precure.ml/@healingoodday)
  - [増子](https://precure.ml/@mikabot)
  - [あくまのめだまニュース](https://mstdn.delmulin.com/@news)
  - [非公式「宮本佳那子のこころをこめて」更新通知ボット](https://mstdn.b-shock.org/@kanako_blog_bot)
  - [ぷーざリリースボット](https://mstdn.b-shock.org/@release_bot)
  - [キュアスタ！お知らせボット](https://precure.ml/@infomation)
  - [デルムリン丼お知らせボット](https://mstdn.delmulin.com/@info)

- 中の人は普段、以下のいずれかに居ます。
  - 個人インスタンス「[美食丼](https://mstdn.b-shock.org/)」
  - プリキュアシリーズ専用インスタンス「[キュアスタ！](https://precure.ml/)」
  - 「ドラゴンクエスト ダイの大冒険」専用インスタンス「[デルムリン丼](https://mstdn.delmulin.com/)」
- プリキュアかダイ大に興味ある人は、遊びに来てください。
