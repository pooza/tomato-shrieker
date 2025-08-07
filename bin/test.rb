#!/usr/bin/env ruby
$LOAD_PATH.unshift(File.join(File.expand_path('..', __dir__), 'app/lib'))

require 'tomato_shrieker'
module TomatoShrieker
  warn Package.full_name
  warn File.basename(__FILE__)
  warn ''
  Sequel.connect(Environment.dsn)
  TestCase.load(ARGV.getopts('', 'cases:')['cases'] || ARGV.first)
rescue => e
  warn e.message
  exit 1
end
