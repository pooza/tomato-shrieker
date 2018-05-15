# サーバモード

Slack互換のwebhookを提供。

## 利用までの流れ

1. local.yamlを設定。
1. `bundle exec rake server:hooks` を実行し、webhookのURLを確認。
1. `bundle exec rake server:start` を実行。
1. あなたのアプリから、 /webhook/v1.0/toot/xxx へPOST。

## ■config/local.yaml設定例

このファイルは640か600のパーミッションを推奨。

```
root_url: https://mstdn.example.com/
salt: 群れをなして襲い掛かってくるつかみ男たち
entries:
  - webhook: true
    mastodon:
      url: https://mstdn.example.com
      token: hogehoge
  - webhook: true
    mastodon:
      url: https://another.mstdn.example.com
      token: hogehoge
slack:
  hook:
    url: https://hooks.slack.com/services/*********/*********/************************
```

## ■要素の説明

以下、YPath表記。

### /root_url

`bundle exec rake server:hooks` を実行した時に、このURLがベースとなる。  
省略した場合は、設置環境から自動的に生成される。

### /salt

webhookのURLを決定する際に、ソルトとして使用される。  
省略可能だが非推奨。省略した場合はlocal.yaml全体がソルトとして使われ、
local.yamlを少しでも書き換えたら、その度にwebhookのURLが変更されるモードになる。

### /entries/*/webhook

サーバモードのためのエントリーである場合は、必ず `true` 。

### /entries/*/mastodon/url

MastodonインスタンスのルートURL。

### /entries/*/mastodon/token

Mastodonの設定画面「開発」で作成できる __アクセストークン__ をコピペ。ほかの情報は要らない。  
また、アクセス権は __write__ 以外は不要。

### /slack/hook/url

指定すれば、実行中の例外がSlackに通知されるようになる。（省略可）  
DiscordのSlack互換Webフックでの動作も確認済み。

## リバースプロキシ設定

Mastodonインスタンスがインストールされたサーバに設置するなら、Mastodon本体同様、
nginxにリバースプロキシを設定する。以下、nginx.confでの設定例。

```
  location ^~ /feed {
    proxy_pass http://localhost:3009;
  }
```

## ■rakeタスク

### bundle exec rake server:hooks

全てのwebhookのURLを表示する。 `/root_url` や `/salt` が影響。

### bundle exec rake server:start

起動

### bundle exec rake server:stop

停止

### bundle exec rake server:restart

再起動

## ■API

### POST /webhook/v1.0/toot/フックID

application/json形式でPOSTすると、対象インスタンスにトゥートを行う。  
jsonの形式は、SlackやDiscordと互換性あり。（Slackを優先）

以下、実行例。

```
curl -H 'Content-Type: application/json' -X POST -d '{"text":"敵が増えてきた時に仕掛けてくるフラッシュ攻撃には気をつけろ！"}' https://mstdn.example.com/webhook/v1.0/toot/xxxx
```

### GET /about

上記設定例ではリバースプロキシを設定していない為、一般ユーザーには公開されないが、
現状はプログラム名とバージョン情報だけを含んだ簡単なJSON文書を出力するので、
必要に応じて監視などに使って頂くとよいと思う。

curlがインストールされているなら、設置先サーバ上で以下実行。

```
curl http://localhost:3009/about -i
```

以下、レスポンス例。

```
HTTP/1.1 200 OK
Content-Type: application/json; charset=UTF-8
Content-Length: 114
X-Content-Type-Options: nosniff
Connection: keep-alive
Server: thin

{"mode":"webhook","request":{"path":"/about","params":{"captures":[]}},"response":{"message":"tomato-toot 2.0.0"}}
```
