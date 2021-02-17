module TomatoShrieker
  class CommandSource < Source
    def exec(options = {})
      return if options['silence']
      command.exec
      raise command.stderr || command.stdout unless command.status.zero?
      command.stdout.split(delimiter).each do |status|
        next unless template = create_template(status)
        params = {text_without_tags: template.to_s}
        template[:tag] = true
        params[:text] = template.to_s
        shriek(params)
      end
      logger.info(source: id, message: 'post')
    end

    def create_template(status)
      return nil unless status.present?
      template = Template.new('common')
      template[:source] = self
      template[:status] = status
      return template
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

    def self.all
      return enum_for(__method__) unless block_given?
      Source.all do |source|
        next unless source.is_a?(CommandSource)
        yield source
      end
    end
  end
end
