# スタンドアロンモード

RSS/Atomフィードの新着エントリーをトゥートする。

## 利用までの流れ

1. local.yamlを設定。
1. standalone.rbを実行。通常はcron等で。

## ■設定例

local.yamlは640か600のパーミッションを推奨。

```
entries:
  - source:
      url: https://blog.b-shock.org/atom.xml
      mode: title
    mastodon:
      url: https://mstdn.example.com
      token: hogehoge
  - prefix: foursquare
    source:
      url: https://feeds.foursquare.com/history/hoge.rss
      mode: summary
    mastodon:
      url: https://mstdn.example.com
      token: hogehoge
  - prefix: foursquare
    source:
      url: https://feeds.foursquare.com/history/hoge.rss
      tag: precure
      mode: summary
    mastodon:
      url: https://mstdn.example.com
      token: hogehoge
  - source:
      url: https://github.com/pooza/radish-feed/releases.atom
    mastodon:
      url: https://mstdn.example.com
      token: hogehoge
    bot_account: true
    shorten: true
slack:
  hook:
    url: https://hooks.slack.com/services/*********/*********/************************
bitly:
  token: hogehoge
```

## ■要素の説明

以下、YPath表記。

### /entries/*/source/url

ソース（RSS/Atomフィード）のURL。  
HTMLファイルのlink要素を読んだりはしないので、フィードのURLを正確に。

### /entries/*/source/mode

title又はsummaryを指定。  
過去のバージョンとの互換性のため、body指定はsummary扱い。  
それ以外の場合は、未指定の場合も含めtitle扱い。  
フィードの種類によって適切な設定は異なる。通常のブログではtitle、
foursquare等ではsummaryが適切と思われる。

### /entries/*/source/tag

ハッシュタグ先頭の `#` を除いたものを指定。（必要ない場合は省略可）  
上記の例ではfoursquareチェックインのうち、本文中に `#precure`  
ハッシュタグがあるものだけをprecure.mlへトゥートする設定にしている。

### /entries/*/source/prefix

文字通り、トゥートされるテキストのプリフィックスを指定。
省略した場合は、フィード自体が持ってるタイトルがプリフィックスとして使用される。

### /entries/*/mastodon/url

MastodonインスタンスのルートURL。

### /entries/*/mastodon/token

Mastodonの設定画面「開発」で作成できる __アクセストークン__ をコピペ。ほかの情報は要らない。  
また、アクセス権は __write__ 以外は不要。

### /entries/*/bot_account

`true` を指定すると、プリフィックスの出力を行わない。

### /entries/*/shorten

`true` を指定すると、URLがbit.lyで短縮される。  
別途 /bitly/token にて、アクセストークンの設定が必要。

### /slack/hook/url

指定すれば、実行中の例外がSlackに通知されるようになる。（省略可）  
DiscordのSlack互換Webフックでの動作も確認済み。

### /bitly/token

短縮URLを使用する場合は、bit.lyのアクセストークンを設定する。  
使用しない場合は省略可。

## ■操作

standalone.rbを実行する。root権限不要。  
通常はcronで5分毎等で起動すればよいと思う。

### シンボリックリンク

1.xとの互換性の為にstandalone.rbへのシンボリックリンクをloader.rbという名前で
配置しているが、廃止予定。  
loader.rbへのシンボリックリンクを作成していた場合は、standalone.rbへ
リンクし直さないと誤動作すると思われる。

### コマンドラインオプション

- `--silence` トゥートを抑止、タイムスタンプの更新のみを行う。（後述）

## ■rakeタスク

### bundle exec rake standalone:run

`standalone.rb` を実行する。
`bundle exec rake run` でも可。

### bundle exec rake standalone:touch

`standalone.rb --silence` を実行、タイムスタンプの更新を行う。
`bundle exec rake rouch` でも可。

### bundle exec rake standalone:clean

tmp/timestamps/*.json を削除し、タイムスタンプ記録を一掃。  
`bundle exec rake clean` でも可。

直後に `bundle exec rake standalone:touch` の実行を推奨。

## ■ふるまい

- 初回起動時に、その時点での最新エントリーの時刻を一時ファイルに記録し、
  そのエントリーをトゥート。次回以降は、その時刻より新しいエントリーが
  トゥートの対象になる。
- フィード設定を少しでも書き換えたら、新しいフィードを登録したとみなす。  
  新規登録時同様、次回の実行では最新エントリーの時刻を記録とトゥートを行い、
  その次以降から実際の処理をはじめる。
- 起動時に `--silence` オプションが指定されている場合は、トゥートを行わない。  
  この場合、最新エントリー時刻の記録のみを行う。
- 例えばGitHubでは、エントリーURLがスキーム（https）とホスト名を含まず、
  不完全なものになってる。これを補う為、エントリーURLが不完全な場合は、
  フィード自体が持ってるサイトのURLから必要な情報を補完し、完全なURLの生成を
  試みる。
