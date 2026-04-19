module TomatoShrieker
  class CommandSource < Source
    def exec
      Bundler.with_unbundled_env {command.exec}
      raise command.stderr || command.stdout unless command.status.zero?
      command.stdout.split(delimiter).map(&:strip).select(&:present?).each do |status|
        template = create_template(:default, status)
        shriek({template:, visibility:})
      end
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
        @command.dir = self['/source/dir'] || Environment.dir
        @command.env = @params.dig('source', 'env') || {}
        @command.env['RUBY_YJIT_ENABLE'] = 'yes' if config['/ruby/jit']
        @command.env['BUNDLE_GEMFILE'] = File.join(@command.dir, 'Gemfile')
        @command.env['RACK_ENV'] ||= Environment.type
      end
      return @command
    end

    def register
      Bundler.with_unbundled_env {command.bundle_install} if bundler?
      return super
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.grep(self).each(&block)
    end
  end
end
