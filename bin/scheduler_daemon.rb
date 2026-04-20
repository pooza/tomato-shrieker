#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.join(File.expand_path('..', __dir__), 'app/lib'))
ENV['RAKE'] = nil

[$stdout, $stderr].each do |io|
  next if io.tty?
  begin
    io.flush
  rescue Errno::EPIPE, IOError
    io.reopen(File::NULL, 'w')
  end
end

require 'tomato_shrieker'
module TomatoShrieker
  SchedulerDaemon.spawn!
end
