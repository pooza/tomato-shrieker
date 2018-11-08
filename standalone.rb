#!/usr/bin/env ruby

path = File.expand_path(__FILE__)
path = File.expand_path(File.readlink(path)) while File.symlink?(path)
ROOT_DIR = File.expand_path('..', path)
$LOAD_PATH.push(File.join(ROOT_DIR, 'lib'))
ENV['BUNDLE_GEMFILE'] ||= File.join(ROOT_DIR, 'Gemfile')
ENV['SSL_CERT_FILE'] ||= File.join(ROOT_DIR, 'cert/cacert.pem')

require 'bundler/setup'
require 'tomato_toot'

TomatoToot::Standalone.new.execute
