module TomatoShrieker
  # ソース種別ごとの既定値 (#1559)。`local.yaml` の `/source_defaults/<クラス名>/...` に書く。
  #
  # 🔴 **解決の規則は「個別の定義にキーがあれば定義、無ければ既定」だけ。**⚠ 仕様を単純に保つ。
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
      name = source_class.to_s.split('::').last
      return KEYS.each_with_object({}) do |key, values|
        path = "/source_defaults/#{name}/#{key}"
        values[key] = config[path] if config.key?(path) && !declared?(params, key)
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

    # ⚠ 途中が `null` なら、その下も書いてあるものとして扱う（外した意図を尊重する）。
    def self.declared?(params, key)
      node = params
      key.split('/').each do |name|
        return false unless node.is_a?(Hash) && node.key?(name)
        node = node[name]
        return true if node.nil?
      end
      return true
    end
  end
end
