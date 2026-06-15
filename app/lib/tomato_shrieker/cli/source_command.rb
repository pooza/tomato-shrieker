# frozen_string_literal: true

require 'shellwords'

module TomatoShrieker
  class SourceCommand < Thor
    include Package

    # `add --class` で生成する雛形の共通パーツ。
    DEFAULT_DEST = {
      'hooks' => ['https://mastodon.example.com/mulukhiya/webhook/CHANGE_ME'],
      'tags' => [],
    }.freeze
    DEFAULT_SCHEDULE = {'cron' => '0 0 * * *'}.freeze

    # `add --class` で生成する種別ごとの雛形。いずれもスキーマ妥当な最小構成。
    TEMPLATES = {
      'feed' => {
        'source' => {'feed' => 'https://example.com/feed'},
        'dest' => DEFAULT_DEST,
      },
      'url' => {
        'source' => {'url' => 'https://example.com/'},
        'dest' => DEFAULT_DEST,
      },
      'news' => {
        'source' => {'news' => {'phrase' => 'CHANGE_ME'}},
        'dest' => DEFAULT_DEST,
      },
      'github' => {
        'source' => {'github' => {'repository' => 'owner/repo', 'timeline' => 'releases'}},
        'dest' => DEFAULT_DEST,
      },
      'icalendar' => {
        'source' => {'ical' => 'https://example.com/calendar.ics'},
        'schedule' => DEFAULT_SCHEDULE,
        'dest' => DEFAULT_DEST,
      },
      'youtube' => {
        'source' => {'youtube' => {'channel' => {'url' => 'https://www.youtube.com/@CHANGE_ME'}}},
        'dest' => DEFAULT_DEST,
      },
      'command' => {
        'source' => {'command' => ['echo', 'hello'], 'dir' => '/path/to/workdir'},
        'schedule' => DEFAULT_SCHEDULE,
        'dest' => DEFAULT_DEST,
      },
      'text' => {
        'source' => {'text' => 'CHANGE_ME'},
        'schedule' => DEFAULT_SCHEDULE,
        'dest' => DEFAULT_DEST,
      },
    }.freeze

    desc 'list', 'ソース一覧 (id とクラス名) を表示'
    def list
      Source.all do |source|
        puts [source.id, source.class.name.split('::').last].join("\t")
      end
    end

    desc 'fetch ID', 'ソースのサマリーを表示'
    def fetch(id)
      source = find_source!(id)
      raise Thor::Error, "source does not support fetch: #{id}" unless source.respond_to?(:summary)
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

    desc 'add ID', '雛形を生成し $EDITOR で編集してソース定義を作成'
    method_option :class, type: :string, default: 'feed',
      desc: "ソース種別 (#{TEMPLATES.keys.join('/')})"
    def add(id)
      path = new_source_path(id)
      raise Thor::Error, "source already exists: #{id}" if File.exist?(path)
      template = TEMPLATES[options[:class]]
      unless template
        raise Thor::Error, "unknown class: #{options[:class]} (#{TEMPLATES.keys.join('/')})"
      end
      File.write(path, template.to_yaml)
      edit_and_validate(id, path)
    end

    desc 'edit ID', '$EDITOR でソース定義を開き、保存後に検証'
    def edit(id)
      edit_and_validate(id, existing_source_path!(id))
    end

    desc 'delete ID', 'ソース定義ファイルを削除（確認付き）'
    def delete(id)
      path = existing_source_path!(id)
      return unless yes?("delete #{path} ? [y/N]")
      File.delete(path)
      say "deleted: #{path}"
    end

    desc 'disable ID', 'ソースを停止 (disable: true)'
    def disable(id)
      set_disable(id, true)
    end

    desc 'enable ID', 'ソースを再開 (disable を解除)'
    def enable(id)
      set_disable(id, false)
    end

    desc 'validate [ID]', 'ソース定義を JSON Schema で検証（ID 省略時は全件）'
    def validate(id = nil)
      paths = id ? [existing_source_path!(id)] : source_paths
      ng = 0
      paths.each do |path|
        errors = SourceValidator.validate(YAML.load_file(path))
        if errors.empty?
          say "OK\t#{source_id(path)}"
        else
          ng += 1
          say "NG\t#{source_id(path)}"
          errors.each {|e| say "    - #{e}"}
        end
      end
      raise Thor::Error, "#{ng} source(s) invalid" if ng.positive?
    end

    private

    def find_source!(id, klass = nil)
      sources = klass ? klass.all : Source.all
      source = sources.find {|v| v.id == id}
      raise Thor::Error, "source not found: #{id}" unless source
      return source
    end

    def edit_and_validate(id, path)
      open_editor(path)
      errors = SourceValidator.validate(YAML.load_file(path))
      if errors.empty?
        say "OK: #{path}"
      else
        warn "WARNING: #{id} の定義にスキーマ違反があります:"
        errors.each {|e| warn "    - #{e}"}
      end
    end

    def open_editor(path)
      editor = ENV['EDITOR'].presence || ENV['VISUAL'].presence || 'vi'
      system(*Shellwords.split(editor), path)
    end

    # コメントやキー順を保つため YAML ラウンドトリップではなく行単位で操作する。
    # トップレベル（インデントなし）の `disable:` 行のみを対象にする。
    def set_disable(id, value)
      path = existing_source_path!(id)
      lines = File.readlines(path)
      if value
        if lines.any? {|v| v.match?(/\Adisable\s*:\s*true\b/)}
          say "already disabled: #{id}"
          return
        end
        lines.insert(lines.first&.start_with?('---') ? 1 : 0, "disable: true\n")
      elsif lines.reject! {|v| v.match?(/\Adisable\s*:\s*(true|false)\b/)}.nil?
        say "already enabled: #{id}"
        return
      end
      File.write(path, lines.join)
      say "#{value ? 'disabled' : 'enabled'}: #{id}"
    end

    def sources_dir
      File.join(Environment.dir, 'config/sources')
    end

    def new_source_path(id)
      File.join(sources_dir, "#{id}.yaml")
    end

    def existing_source_path!(id)
      path = source_paths.find {|v| source_id(v) == id}
      raise Thor::Error, "source not found: #{id}" unless path
      return path
    end

    def source_paths
      Dir.glob(File.join(sources_dir, '*.{yaml,yml}'))
    end

    def source_id(path)
      File.basename(path).sub(/\.ya?ml\z/, '')
    end
  end
end
