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
        self.class.to_s,
        Package.full_name,
      ].join("\n")
    end
  end
end
