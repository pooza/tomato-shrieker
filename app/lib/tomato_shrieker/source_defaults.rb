module TomatoShrieker
  # ソース種別ごとの既定値 (#1559)。`config/local.yaml` の `/source_defaults/<クラス名>/...` に書く。
  #
  # **解決の規則は「個別の定義にキーがあれば定義、無ければ既定」だけ。**⚠ 仕様を単純に保つ。
  # - 効くのは完全に同じクラスだけ（継承しない）
  # - 書けるのは `KEYS` だけ。スケジュールや宛先は個別に書く
  # - 定義に `null` を書けば、そのソースだけ既定を外せる（`retry: null` なら `retry` の下のキーも）
  #
  # 📌 どのキーが既定から来たかは `/status.json` の `source_defaults` に出る。
  module SourceDefaults
    KEYS = [
      'monitor/tolerance',
      'monitor/silence_tolerance',
      'monitor/error_streak_threshold',
      'schedule/retry/times',
      'schedule/retry/interval',
    ].freeze

    # このソースに効く既定値を `{'monitor/tolerance' => '10m'}` の形で返す。
    def self.values_for(source_class, params)
      config = Config.instance
      # ⚠ `Config` はキーを小文字にして持つ（ginseng-core の `key_flatten`）。4.19.0 リリース前レビュー。
      name = source_class.to_s.split('::').last.downcase
      return KEYS.each_with_object({}) do |key, values|
        # ⚠ `Config#[]` は無いキーと空の値で例外を上げる。`Source.new` で上げると全ソースが止まる。
        value = config.fetch("/source_defaults/#{name}/#{key}", nil)
        values[key] = value unless value.nil? || declared?(params, key)
      end
    end

    # 既定値を足した定義を返す。⚠ 元の定義は `/sources` の実物なので書き換えない。
    def self.apply(params, values)
      merged = params.deep_dup
      values.each do |key, value|
        *parents, leaf = key.split('/')
        node = parents.inject(merged) {|hash, name| hash[name] ||= {}}
        node[leaf] = value
      end
      return merged
    end

    # ⚠ 途中が Hash でないなら、その下も書いてあるものとして扱う。`null` は外した意図を尊重する。
    # 文字列などのスキーマ違反は `source validate` の領分で、ここで倒すと全ソースが止まる。
    def self.declared?(params, key)
      node = params
      key.split('/').each do |name|
        return true unless node.is_a?(Hash)
        return false unless node.key?(name)
        node = node[name]
      end
      return true
    end
  end
end
