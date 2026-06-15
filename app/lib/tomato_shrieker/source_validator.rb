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
    end
  end
end
