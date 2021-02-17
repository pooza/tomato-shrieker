module TomatoShrieker
  class TextSource < Source
    def exec(options = {})
      shriek(
        text: create_body(tag: true),
        text_without_tags: create_body,
        visibility: visibility,
      )
      logger.info(source: id, message: 'post')
    end

    def create_body(params = {})
      template = Template.new('common')
      template.params = params
      template[:status] = text
      template[:source] = self
      return template.to_s.strip
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
