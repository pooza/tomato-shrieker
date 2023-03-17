module TomatoShrieker
  class SchedulerDaemon < Ginseng::Daemon
    include Package

    def command
      command = Ginseng::CommandLine.new([
        File.join(Environment.dir, 'bin/scheduler_worker.rb'),
      ])
      command.env['RUBY_YJIT_ENABLE'] = 'yes' if config['/ruby/jit']
      command.env['BUNDLE_GEMFILE'] = File.join(Environment.dir, 'Gemfile')
      command.env['RACK_ENV'] ||= Environment.type
      return command
    end

    def motd
      return [
        "#{self.class} #{Package.version}",
        ('Ruby YJIT: Ready' if jit_ready?),
      ].compact.join("\n")
    end
  end
end
