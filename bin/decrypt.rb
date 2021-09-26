#!/usr/bin/env ruby
dir = File.expand_path('..', __dir__)
$LOAD_PATH.unshift(File.join(dir, 'app/lib'))
ENV['BUNDLE_GEMFILE'] = File.join(dir, 'Gemfile')

require 'tomato_shrieker'
module TomatoShrieker
  warn Package.full_name
  warn '復号化ユーティリティ'
  warn ''

  raise '/crypt/password が未設定です。' unless Crypt.config?
  password = ARGV.first
  raise '文字列を指定してください。' unless password.present?
  puts password.decrypt
rescue => e
  warn e.message
  exit 1
end
