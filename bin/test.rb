#!/usr/bin/env ruby
$LOAD_PATH.unshift(File.join(File.expand_path('..', __dir__), 'app/lib'))

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
