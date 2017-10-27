#!/usr/bin/env ruby
ROOT_DIR = File.expand_path('..', __FILE__)
$LOAD_PATH.push(File.join(ROOT_DIR, 'lib'))
ENV['BUNDLE_GEMFILE'] ||= File.join(ROOT_DIR, 'Gemfile')

require 'optparse'
require 'tomato-toot/application'

TomatoToot::Application.new.execute(
  ARGV.getopts('', 'all')
)
