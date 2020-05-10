module TomatoToot
  class TextSource < Source
    def exec(options = {})
      mastodon&.toot(status: text, visibility: visibility)
      hooks {|hook| hook.say({text: text}, :hash)}
      logger.info(source: hash, message: 'post')
    end

    def text
      return self['/source/text']
    end
  end
end
