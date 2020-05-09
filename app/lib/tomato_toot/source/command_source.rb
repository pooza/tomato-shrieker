module TomatoToot
  class CommandSource < Source
    def exec(options = {})
      command.exec
      raise command.stderr || command.stdout unless command.status.zero?
      text = command.stdout
      mastodon&.toot(status: text, visibility: visibility)
      hooks {|hook| hook.say({text: text}, :hash)}
      logger.info(source: hash, message: 'post')
    end

    def command
      args = self['/source/command']
      args = [args] unless args.is_a?(Array)
      @command ||= Ginseng::CommandLine.new(args)
      return @command
    end
  end
end
