# tomato-toot

RSS/Atomフィードの新着エントリーをトゥートする。

## ■設置の手順

- 常時起動のUNIX系サーバでさえあれば、どこでも設置可。

### リポジトリをクローン

```
git clone git@github.com:pooza/tomato-toot.git
```

クローンを行うとローカルにリポジトリが作成されるが、このディレクトリの名前は
変更しないことを推奨。（syslogのプログラム名や、設定ファイルのパス等に影響）

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
      url: https://github.com/pooza/radish-feed/releases.atom
      prefix: null
    mastodon:
      url: https://mstdn.b-shock.org
      token: hogehoge
slack:
  hook:
    url: https://hooks.slack.com/services/*********/*********/************************
```

- source内のmodeは、titleかbody。（titleの場合は省略可）  
  フィードの種類によって適切な設定は異なる。例えば、foursquareではbody（本文）を
  トゥートしないと情報量が全然足りないけど、通常のブログではtitle（タイトル）じゃないと
  文字数が収まらない。
- source内のtagは、ハッシュタグ先頭の # を除いたものを指定。（必要ない場合は省略可）  
  上記の例ではfoursquareチェックインのうち、本文中に #precure ハッシュタグがある
  ものだけをprecure.mlへトゥートする設定にしている。
- source内prefixは、文字通り、トゥートされるテキストのプリフィックスを指定。
  省略した場合は、フィード自体が持ってるタイトルがプリフィックスとして使用される。
  また、 `null` を指定すると、プリフィックスの出力を行わない。
- mastodon内のtokenは、Mastodonの設定画面「開発」で作成する。  
  作成後に表示される __アクセストークン__ をコピペ。ほかの情報は要らない。  
  また、アクセス権は __write__ 以外は不要。
- SlackのWebフックを指定すれば、実行中の例外がSlackに通知されるようになる。（省略可）  
  また、DiscordのSlack互換Webフックでの動作も確認済み。

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

- 初回起動時に、その時点での最新エントリーの時刻を一時ファイルに記録し、
  そのエントリーをトゥート。次回以降は、その時刻より新しいエントリーが
  トゥートの対象になる。
- フィード設定を少しでも書き換えたら、新しいフィードを登録したとみなす。  
  新規登録時同様、次回の実行では最新エントリーの時刻を記録とトゥートを行い、
  その次以降から実際の処理をはじめる。
- 例えばGitHubでは、エントリーURLがスキーム（https）とホスト名を含まず、
  不完全なものになってる。これを補う為、エントリーURLが不完全な場合は、
  フィード自体が持ってるサイトのURLから必要な情報を補完し、完全なURLの生成を
  試みる。

## ■設定ファイルの検索順

local.yamlは、上記設置例ではconfigディレクトリ内に置いているが、
実際には以下の順に検索している。（ROOT_DIRは設置先）

- /usr/local/etc/tomato-toot/local.yaml
- /usr/local/etc/tomato-toot/local.yml
- /etc/tomato-toot/local.yaml
- /etc/tomato-toot/local.yml
- __ROOT_DIR__/config/local.yaml
- __ROOT_DIR__/config/local.yml

ファイルが発見できた時点で、以降の検索をやめる。
