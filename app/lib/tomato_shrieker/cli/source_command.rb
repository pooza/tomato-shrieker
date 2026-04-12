# frozen_string_literal: true

module TomatoShrieker
  class SourceCommand < Thor
    include Package

    desc 'list', 'ソース一覧を表示'
    def list
      Source.all do |source|
        puts source.to_h.deep_stringify_keys.to_yaml
      end
    end

    desc 'fetch ID', 'ソースのサマリーを表示'
    def fetch(id)
      source = find_source!(id)
      puts source.summary.deep_stringify_keys.to_yaml
    end

    desc 'shriek ID', 'ソースを実行（投稿）'
    def shriek(id)
      source = find_source!(id)
      source.exec
    end

    desc 'touch ID', 'ソースをタッチ'
    def touch(id)
      source = find_source!(id, FeedSource)
      source.touch
    end

    desc 'clear ID', 'ソースのレコードをすべて削除'
    def clear(id)
      source = find_source!(id, FeedSource)
      source.clear
    end

    private

    def find_source!(id, klass = nil)
      sources = klass ? klass.all : Source.all
      source = sources.find {|v| v.id == id}
      raise Thor::Error, "source not found: #{id}" unless source
      return source
    end
  end
end
