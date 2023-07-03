# tomato-shrieker

![release](https://img.shields.io/github/v/release/pooza/tomato-shrieker.svg)
![test](https://github.com/pooza/tomato-shrieker/workflows/test/badge.svg)

## できること

- 会話をしない単純なつぶやきボットを作成するツールです。
- 投稿のソース・投稿先・スケジュールの3要素を組み合わせて、定義ファイル（YAML形式）に記述します。
- 定義ファイルに複数のボットを定義し、まとめて管理することが出来ます。
- 詳細は[wiki](https://github.com/pooza/tomato-shrieker/wiki)にて。

### 投稿のソース

- 定型文
- RSS/Atomフィードの新着エントリー
- Google News
- GitHubリポジトリのリリース履歴
- コマンドの実行結果（標準出力）

### 投稿先

- [Mastodon](https://github.com/tootsuite/mastodon)
  - [Pleroma](https://git.pleroma.social/pleroma)等、互換APIをもつサービスを含む。
- [Misskey](https://github.com/syuilo/misskey)
- Slack Incoming Webhooks
  - Discord等、webhookに互換性をもつサービスを含む。
  - 拙作[モロヘイヤ](https://github.com/pooza/mulukhiya-toot-proxy)を含む。
- [Lemmy](https://github.com/LemmyNet/lemmy/)
- LINE

### スケジュール

- 定期的に（デフォルトは5分ごと）
- 指定時刻
- cron形式の指定

## 由来

- forsquareのチェックインを自動投稿する用途が最初でした。プリキュア関連のニュースボットのエンジンとして利用を始めたのがその次です。
- いずれも、Atom/RSSフィードからMastodonへ投稿（トゥート）を行う仕様でした。その為、この頃はtomato-tootという名前でした。

## 宣伝

- 以下のボットのパーツとして使われています。
  - [増子](https://precure.ml/@mikabot) （[紹介記事](https://blog.precure.ml/articles/%E5%A2%97%E5%AD%90/)）
  - [あくまのめだまニュース](https://mstdn.delmulin.com/@news) （[紹介記事](https://blog.delmulin.com/articles/%E3%81%82%E3%81%8F%E3%81%BE%E3%81%AE%E3%82%81%E3%81%A0%E3%81%BE/)）
  - [「シュビドゥビ☆スイーツタイム」の再生回数を淡々と喋るボット](https://mstdn.b-shock.org/@shooby_do_bop_bot)
  - [「レッツ・ラ・クッキン☆ショータイム」の再生回数ボット](https://mstdn.b-shock.org/@lets_la_bot)
  - [「エビバディ☆ヒーリングッデイ！」再生数ボット](https://precure.ml/@healingoodday)
  - [「勇気の刃」キュアソードラブリンクBot](https://mk.precure.fun/@cureswordlovelinkbot)
  - [非公式「宮本佳那子のこころをこめて」更新通知ボット](https://mstdn.b-shock.org/@kanako_blog_bot)
  - [ぷーざリリースボット](https://mstdn.b-shock.org/@release_bot)
  - [ぷーざの録画状況ボット](https://reco.shrieker.net/@pooza_recorder_bot)
  - [キュアスタ！お知らせボット](https://precure.ml/@infomation)
  - [デルムリン丼お知らせボット](https://mstdn.delmulin.com/@info)

- 中の人は普段、以下のいずれかに居ます。
  - 個人サーバー「[美食丼](https://mstdn.b-shock.org/)」
  - プリキュアシリーズ専用Mastodonサーバー「[キュアスタ！](https://precure.ml/)」
  - プリキュアシリーズ専用Misskeyサーバー「[きゅあすきー](https://mk.precure.fun/)」
  - 「ドラゴンクエスト ダイの大冒険」専用Mastodonサーバー「[デルムリン丼](https://mstdn.delmulin.com/)」
  - 「ドラゴンクエスト ダイの大冒険」専用Misskeyサーバー「[ダイスキー](https://misskey.delmulin.com/)」
- きゅあすきーだけ自鯖ではないです。
- プリキュアかダイ大に興味ある人は、遊びに来てください。
