# frozen_string_literal: true

require 'json-schema'

module TomatoShrieker
  # 単一ソース定義（config/sources/<id>.yaml）を config/schema/source.yaml で検証する。
  class SourceValidator
    include Package

    JSON::Validator.use_multi_json = false

    SCHEMA_FILE = 'config/schema/source.yaml'

    class << self
      def schema
        @schema ||= YAML.load_file(File.join(Environment.dir, SCHEMA_FILE))
      end

      # 検証エラーの配列を返す（空 = 妥当）。params は Hash（YAML ロード済みのソース定義）。
      # json-schema が付与する末尾の「 in schema <uuid>」は可読性のため除去する。
      def validate(params)
        JSON::Validator.fully_validate(schema, params.deep_stringify_keys)
          .map {|message| message.sub(/ in schema [0-9a-f-]+\z/, '')}
      end

      def valid?(params)
        validate(params).empty?
      end

      # スキーマは通るが運用上の穴になる設定の配列を返す（空 = 指摘なし）。
      # errors と違い NG にはしない。silence_tolerance は opt-in なので未指定でも
      # 妥当だが、宣言しなければサイレント不発の検知が丸ごと効かない (#1470)。
      def warnings(params)
        params = params.deep_stringify_keys
        return [] if params['disable'] == true
        return [] if params.dig('schedule', 'at')
        return [] if params.dig('monitor', 'silence_tolerance')
        return ['/monitor/silence_tolerance が未設定です。無配信が続いても検知されません']
      end
    end
  end
end
