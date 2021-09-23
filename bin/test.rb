#!/usr/bin/env ruby
dir = File.expand_path('..', __dir__)
$LOAD_PATH.unshift(File.join(dir, 'app/lib'))
ENV['BUNDLE_GEMFILE'] = File.join(dir, 'Gemfile')

require 'tomato_shrieker'
module TomatoShrieker
  warn Package.full_name
  warn 'テストローダー'
  warn ''
  TestCase.load(ARGV.getopts('', 'cases:')['cases'])
rescue => e
  warn e.message
  exit 1
end
