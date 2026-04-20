#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.join(File.expand_path('..', __dir__), 'app/lib'))
ENV['RAKE'] = nil

$stdin.reopen(File::NULL, 'r') unless $stdin.tty?
[$stdout, $stderr].each do |io|
  io.reopen(File::NULL, 'w') unless io.tty?
end

require 'tomato_shrieker'
module TomatoShrieker
  SchedulerDaemon.spawn!
end
