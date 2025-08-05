#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.join(File.expand_path('..', __dir__), 'app/lib'))
ENV['RAKE'] = nil

require 'tomato_shrieker'
#TomatoShrieker.setup_database
#TomatoShrieker.loader.eager_load
TomatoShrieker::Scheduler.instance.exec
