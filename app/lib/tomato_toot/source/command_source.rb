module TomatoToot
  class CommandSource < Source
    def exec(options = {})
      return if options['silence']
      command.exec
      raise command.stderr || command.stdout unless command.status.zero?
      statuses do |status|
        mastodon&.toot(status: status, visibility: visibility)
        hooks {|hook| hook.say({text: status}, :hash)}
      end
      logger.info(source: hash, message: 'post')
    end

    def statuses
      command.stdout.split(delimiter).each do |status|
        template = Template.new('toot.common')
        template[:status] = status
        template[:source] = self
        status = template.to_s.strip
        yield status if status.present?
      end
    end

    def delimiter
      return Regexp.new("#{self['/source/delimiter'] || '====='}\n?")
    end

    def command
      unless @command
        args = self['/source/command']
        args = [args] unless args.is_a?(Array)
        @command = Ginseng::CommandLine.new(args)
        @command.dir = self['/source/dir']
      end
      return @command
    end
  end
end
