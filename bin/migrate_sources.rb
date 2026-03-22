#!/usr/bin/env ruby
$LOAD_PATH.unshift(File.join(File.expand_path('..', __dir__), 'app/lib'))

require 'tomato_shrieker'
module TomatoShrieker
  warn Package.full_name
  warn File.basename(__FILE__)
  warn ''

  local_path = Config.instance.local_file_path
  raise 'local.yaml が見つかりません。' unless local_path

  local = YAML.load_file(local_path)
  sources = local.delete('sources')
  raise 'local.yaml に sources が定義されていません。' if sources.nil? || sources.empty?

  sources_dir = File.join(Environment.dir, 'config/sources')
  count = 0

  sources.each do |source|
    source = source.deep_stringify_keys
    id = source.delete('id') || Digest::SHA1.hexdigest(source.to_json)
    dest = File.join(sources_dir, "#{id}.yaml")

    if File.exist?(dest)
      warn "skip: #{id} (already exists)"
      next
    end

    File.write(dest, source.to_yaml)
    warn "create: #{dest}"
    count += 1
  end

  File.write(local_path, local.to_yaml)
  warn ''
  warn "#{count} source(s) migrated."
  warn 'local.yaml から sources を除去しました。'
rescue => e
  warn e.message
  exit 1
end
