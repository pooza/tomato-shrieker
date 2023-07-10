#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.join(File.expand_path('..', __dir__), 'app/lib'))
ENV['RAKE'] = nil

require 'tomato_shrieker'
module TomatoShrieker
  include Package
  op = ARGV.first
  SchedulerDaemon.spawn!
  puts config.secure_dump.to_yaml if op == 'start'
end
