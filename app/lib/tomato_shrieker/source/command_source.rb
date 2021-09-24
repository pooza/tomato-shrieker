module TomatoShrieker
  class CommandSource < Source
    def exec
      command.exec
      raise command.stderr || command.stdout unless command.status.zero?
      command.stdout.split(delimiter).each do |status|
        shriek(template: create_template(status), visibility: visibility)
      rescue => e
        logger.error(source: id, error: e, status: status)
      end
    rescue => e
      e.package = Package.full_name
      WebhookShrieker.broadcast(e)
      logger.error(source: id, error: e)
    end

    def create_template(status)
      return nil unless status.present?
      template = self.template.clone
      template[:source] = self
      template[:status] = status
      return template
    end

    def bundler?
      return command.to_s.match?(/^bundler? /)
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

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.select {|s| s.is_a?(CommandSource)}.each(&block)
    end
  end
end
