module TomatoShrieker
  class TextSource < Source
    def exec
      shriek(template: template, visibility: visibility)
    rescue => e
      e.package = Package.full_name
      SlackService.broadcast(e)
      logger.error(source: id, error: e)
    end

    def templates
      @templates ||= super.transform_values {|v| v.merge(status: text, source: self)}
      return @templates
    end

    def text
      return self['/source/text']
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.select {|s| s.is_a?(TextSource)}.each(&block)
    end
  end
end
