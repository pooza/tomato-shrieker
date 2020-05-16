module TomatoToot
  class TextSource < Source
    def exec(options = {})
      mastodon&.toot(status: status, visibility: visibility)
      hooks {|hook| hook.say({text: status}, :hash)}
      logger.info(source: hash, message: 'post')
    end

    def status
      template = Template.new('toot.common')
      template[:status] = text
      template[:source] = self
      return template.to_s
    end

    def text
      return self['/source/text']
    end
  end
end
