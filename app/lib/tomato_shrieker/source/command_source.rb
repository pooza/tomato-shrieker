module TomatoShrieker
  class CommandSource < Source
    def exec(options = {})
      return if options['silence']
      command.exec
      raise command.stderr || command.stdout unless command.status.zero?
      statuses do |status|
        shriek(text: status, visibility: visibility)
      end
      logger.info(source: hash, message: 'post')
    end

    def statuses
      command.stdout.split(delimiter).each do |status|
        template = Template.new('common')
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
        @command = Ginseng::CommandLine.new
        if self['/source/command'].is_a?(Array)
          @command.args = self['/source/command']
        else
          @command.args.push('sh')
          @command.args.push('-c')
          @command.args.push(self['/source/command'])
        end
        @command.dir = self['/source/dir']
        @command.env = @params.dig('source', 'env') || {}
      end
      return @command
    end
  end
end
