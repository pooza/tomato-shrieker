#!/usr/bin/env ruby

path = File.expand_path(__FILE__)
path = File.expand_path(File.readlink(path)) while File.symlink?(path)
dir = File.expand_path('../..', path)
$LOAD_PATH.unshift(File.join(dir, 'lib'))
ENV['BUNDLE_GEMFILE'] ||= File.join(dir, 'Gemfile')
ENV['SSL_CERT_FILE'] ||= File.join(dir, 'cert/cacert.pem')

require 'bundler/setup'
require 'tomato_toot'

TomatoToot::Feed.crawl_all
