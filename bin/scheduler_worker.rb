#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.join(File.expand_path('..', __dir__), 'app/lib'))
ENV['RAKE'] = nil

require 'tomato_shrieker'
TomatoShrieker::Scheduler.instance.exec
