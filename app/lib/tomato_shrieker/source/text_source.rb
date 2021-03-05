module TomatoShrieker
  class TextSource < Source
    def exec(options = {})
      shriek(template: template, visibility: visibility)
      logger.info(source: id, message: 'post')
    end

    def template
      template = Template.new('common')
      template[:status] = self['/source/text']
      template[:source] = self
      return template
    end

    def self.all
      return enum_for(__method__) unless block_given?
      return Source.all.select {|s| s.is_a?(TextSource)}
    end
  end
end
