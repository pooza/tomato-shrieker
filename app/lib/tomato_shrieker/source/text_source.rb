module TomatoShrieker
  class TextSource < Source
    def exec
      shriek(template: create_template, visibility:)
    rescue => e
      e.package = Package.full_name
      SlackService.broadcast(e)
      logger.error(source: id, error: e)
    end

    def create_template(type = :default, status = nil)
      template = super
      template[:status] = status || text
      return template
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
