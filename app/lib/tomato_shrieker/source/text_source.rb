module TomatoShrieker
  class TextSource < Source
    def exec(options = {})
      shriek(text: status, visibility: visibility)
      logger.info(source: id, message: 'post')
    end

    def status
      template = Template.new('common')
      template[:status] = text
      template[:source] = self
      return template.to_s
    end

    def text
      return self['/source/text']
    end

    def self.all
      return enum_for(__method__) unless block_given?
      Source.all do |source|
        next unless source.is_a?(TextSource)
        yield source
      end
    end
  end
end
