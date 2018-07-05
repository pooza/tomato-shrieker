# tomato-toot

Mastodonむけ、トゥート支援ツール。

- RSS/Atomフィードの新着エントリーをトゥートする。
- Slack/Discord互換のwebhookを提供。

## ■設置の手順

常時起動のUNIX系サーバであれば、どこでも設置可。

### リポジトリをクローン

```
git clone git@github.com:pooza/tomato-toot.git
```

### 依存するgemのインストール

```
cd tomato-toot
bundle install
```

### syslog設定

tomato-tootというプログラム名で、syslogに出力している。  
以下、rsyslogでの設定例。

```
:programname, isequal, "tomato-toot" -/var/log/tomato-toot.log
```

### スタンドアロンモードの設定

Atom/RSSフィードをソースとしたトゥートを行うなら。  
[スタンドアロンモード](doc/standalone.md)の設定を行い、local.yamlの編集以降の
手順に対応。

### サーバモードの設定

Slack/Discord互換webhookからトゥートを行うなら。  
[サーバモード](doc/server.md)の設定を行い、local.yamlの編集以降の
手順に対応。

## ■更新適用の手順

新バージョンの適用は、以下の手順で行う。

```
cd 設置先
git fetch
git checkout バージョン名
bundle install
bundle exec rake clean
bundle exec rake touch
```

## ■設定ファイルの検索順

local.yamlは以下の順に検索しているので、どこにあってもよい。（ROOT_DIRは設置先）

- /usr/local/etc/tomato-toot/local.yaml
- /usr/local/etc/tomato-toot/local.yml
- /etc/tomato-toot/local.yaml
- /etc/tomato-toot/local.yml
- __ROOT_DIR__/config/local.yaml
- __ROOT_DIR__/config/local.yml

## ■宣伝

- 中の人は普段、個人インスタンス「[美食丼](https://mstdn.b-shock.org/)」か、
プリキュア専用インスタンス「[キュアスタ！](https://precure.ml/)」に居ます。
プリキュアに興味ある人は、是非キュアスタ！を覗いてね！

- このtomato-toot、以下の拙作BOTのバーツとしても使われています。
  - [「東映アニメーション プリキュア公式」の新着情報ボット](https://precure.ml/@toei_bot)
  - [「ABC毎日放送 プリキュア公式」の新着情報ボット](https://precure.ml/@abc_bot)
  - [「プリキュアガーデン」の新着情報ボット](https://precure.ml/@garden_bot)
  - [「プリキュア公式YouTubeチャンネル」の新着情報ボット](https://precure.ml/@youtube_precure_bot)