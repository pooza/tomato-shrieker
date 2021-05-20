module TomatoShrieker
  class SchedulerDaemon < Ginseng::Daemon
    include Package

    def command
      return Ginseng::CommandLine.new([
        File.join(Environment.dir, 'bin/scheduler_worker.rb'),
      ])
    end

    def motd
      return [
        "#{self.class} #{Package.version}",
      ].join("\n")
    end
  end
end
