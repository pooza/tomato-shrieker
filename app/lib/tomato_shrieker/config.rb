module TomatoShrieker
  class Config < Ginseng::Config
    include Package

    # 🔴 **ファイルを全部読み切ってから、self へは 1 回だけ書く (#1530)。**
    #
    # 以前は `self['/sources']` へ 1 件ずつ push していた。2 つの穴があった。
    #
    # 1. **途中で失敗すると戻せない。** 1 ファイルが `Psych::SyntaxError` を
    #    上げると、`/sources` は**途中まで積まれた状態で残る**。⚠ ソース定義を
    #    手で 1 文字打ち間違えただけで、稼働中のソース一覧が壊れた
    # 2. **途中経過が監視から見える。** push している間 `/sources` は短いまま。
    #    ⚠ `/status.json` は全ソースを舐めるので約 900ms かかり（#1472）、
    #    この窓に重なると**ソースが欠けて見える**。`/healthz/source/:id` は
    #    `Source.create(id)` が見つからず **404** を返す。Kuma に偽の 404 / 503 が出る
    #
    # ⚠ **`source_entries` を `super` より先に呼ぶこと。** ファイル I/O を先に
    # 済ませておけば、`super` の `update` と下の代入の間に I/O が挟まらず、
    # 窓はマイクロ秒まで縮む。壊れた YAML があれば `self` を一切変更しないまま
    # raise するので、呼び出し側は前の内容のまま走り続ける。
    #
    # ⚠ `+` で新しい配列を作る。`super` が返す配列は `@raw` の実体そのものなので、
    # そこへ push すると load のたびに積み増さる（ginseng-core#491）。
    # ⚠ **公開は 1 手にする (#1548)。**`super` は self を直接 `update` するので、
    # そのままだと `/sources` が `application.yaml` の値（＝ `[]`）へ戻り、
    # **完成するまでの間、読み手には空の一覧が見える**。⚠ 窓を短くしても消えない。
    # `update` を横流しして完成品を組み立て、**1 回の `replace`** で公開する
    # （MRI の `Hash#replace` は C で完結するので中間状態が見えない）。
    def load
      entries = source_entries
      @staging = {}
      begin
        super
        staged = @staging
        staged['/sources'] = (staged['/sources'] || []) + entries
      ensure
        @staging = nil
      end
      replace(staged)
    end

    # ⚠ `load` の最中だけ横流しする。ここを素通しにすると `super` が self を
    # 書き換え、上の「公開は 1 手」が崩れる。
    def update(other)
      return @staging.update(other) if @staging
      return super
    end

    # `config/sources/*.yaml` を読んで配列にする。⚠ self には触らない。
    def source_entries
      return suffixes.flat_map do |suffix|
        Dir.glob(File.join(Environment.dir, 'config/sources', "*#{suffix}")).map do |f|
          values = YAML.load_file(f)
          values['id'] ||= File.basename(f, suffix)
          values
        end
      end
    end

    # Ginseng::Config の `alias reload load` は親の load を束縛するため、
    # そのままでは config/sources/*.yaml を読み直さず全ソースが消える。
    def reload
      return load
    end

    def secure_dump
      return filter(self['/sources'])
    end

    private

    def filter(arg)
      case arg
      in Hash
        arg.deep_stringify_keys!
        arg.each do |k, v|
          next if v.to_s.empty?
          if k == 'password'
            arg.delete(k)
          else
            arg[k] = filter(v)
          end
        end
      in Array
        arg.each_with_index do |v, i|
          next if v.to_s.empty?
          arg[i] = filter(v)
        end
      else
      end
      return arg
    end
  end
end
