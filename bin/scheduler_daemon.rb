#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.join(File.expand_path('..', __dir__), 'app/lib'))
ENV['RAKE'] = nil

require 'tomato_shrieker'
module TomatoShrieker
  include Package
  SchedulerDaemon.spawn!
  # puts config.secure_dump.to_yaml
end
