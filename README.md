# tomato-toot

RSS/Atomの新着エントリーをトゥートする。

## ■設置の手順

- 常時起動のUNIX系サーバでさえあれば、どこでも設置可。  
  macOS/FreeBSDでの動作を確認、要するにWindows以外はOK。（Winは対応予定なし）
- 設置先がMastodonインスタンスのサーバである必要は、必ずしもなし。

### リポジトリをクローン

```
git clone git@github.com:pooza/tomato-toot.git
```

### 依存するgemのインストール

```
cd tomato-toot
bundle install
```

### local.yamlを編集

```
vi config/local.yaml
```

以下、設定例。

```
entries:
  - prefix: foursquare
    source:
      url: https://feeds.foursquare.com/history/hoge.rss
      mode: body
    mastodon:
      url: https://mstdn.b-shock.org
      token: hogehoge
  - prefix: foursquare
    source:
      url: https://feeds.foursquare.com/history/hoge.rss
      tag: precure
      mode: body
    mastodon:
      url: https://precure.ml
      token: hogehoge
  - source:
      url: https://blog.b-shock.org/atom.xml
      mode: title
    mastodon:
      url: https://mstdn.b-shock.org
      token: hogehoge
  - source:
      url: https://github.com/pooza/radish-feed/releases.atom
      mode: title
    mastodon:
      url: https://mstdn.b-shock.org
      token: hogehoge
  - source:
      url: https://github.com/pooza/onionbot/releases.atom
      mode: title
    mastodon:
      url: https://mstdn.b-shock.org
      token: hogehoge
```

上記設定は、実際に使ってるもの。（但し、トークンとかは当然伏せてる）
こんなふうに、複数のフィードを登録して、一度に処理できる。
設定に奇をてらったところはなく、大体見ての通りだと思っているが。  
以下、特に注意するところ。

- source内のmodeは、titleかbody。フィードの種類によって適切な設定が異なる。  
  例えば、foursquareではbody（本文）をトゥートしないと情報量が全然
  足りないけど、ふつうのブログではタイトルじゃないと文字数に収まらない。
- source内のtagは、ハッシュタグ先頭の # 除いたものを指定。  
  上記の例では、foursquareチエックインのうち #precure ハッシュタグのある
  ものだけをprecure.mlにトゥートする設定にしている。
- source内prefixは、トゥートされるテキストの文字通りプリフィックスを指定。
  指定しない場合は、フィード自体が持ってるタイトルが使用される。
- mastodon内のtokenは、Mastodonの設定画面「開発」で作成する。  
  作成後に表示される __アクセストークン__ をコピペ。ほかの情報は要らない。  
  また、アクセス権は __write__ 以外は不要。

### syslog設定

tomato-tootというプログラム名で、syslogに出力している。  
必要に応じて、適宜設定。以下、rsyslogでの設定例。

```
:programname, isequal, "tomato-toot" -/var/log/tomato-toot.log
```

## ■操作

loader.rbを実行する。root権限不要。  
通常はcronで5分毎等で起動すればよいと思う。

## ■ふるまい

- 初回起動時に、その時点での最新エントリーの時刻を一時ファイルに記録。
  次回以降、その時刻より新しいエントリーがトゥートの対象になる。
- フィード設定を少しでも書き換えたら、新しいフィードを登録したとみなす。  
  新規登録時同様、次回の実行では単に最新エントリーの時刻を記録し、
  その次以降から実際の処理をはじめる。
- 例えばGitHubでは、エントリーURLがスキーム（https）とホスト名を含まず、
  不完全なものになってる。これを補う為、エントリーURLが不完全な場合は、
  フィード自体が持ってるサイトのURLから必要な情報を補完し、完全なURLの生成を
  試みる。

## ■おことわり

上の設定例にある様に、

- foursquareのチェックイン履歴
- 個人ブログ（Hexo）
- GitHubのリリースタグ一覧

のフィードでしか試していない。  
個人的にはこれ以上必要ないので満足しているが、万一不具合が発生したら、
Issueを作成して頂ければ、気が向いたら修正させて頂く。
