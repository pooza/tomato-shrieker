#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.join(File.expand_path('..', __dir__), 'app/lib'))
ENV['RAKE'] = nil

require 'tomato_shrieker'
module TomatoShrieker
  SchedulerDaemon.spawn!
end
