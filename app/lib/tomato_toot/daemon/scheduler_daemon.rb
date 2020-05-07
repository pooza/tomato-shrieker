module TomatoToot
  class SchedulerDaemon < Ginseng::Daemon
    include Package

    def command
      return Ginseng::CommandLine.new([
        File.join(Environment.dir, 'bin/scheduler_worker.rb'),
      ])
    end

    def motd
      return [
        Package.full_name,
      ].join("\n")
    end
  end
end
