module TomatoShrieker
  class NewsEntry < Entry
    def self.create(entry, feed = nil)
      values = values.is_a?(Hash) ? entry.clone : values.to_h unless values.is_a?(Hash)
      feed ||= Source.create(values['feed'])
      return if feed.touched? && entry['published'] <= feed.time
      id = insert(
        feed: feed.id,
        title: create_title(values['title'], feed),
        summary: values['summary']&.sanitize,
        url: values['url'],
        published: values['published'].getlocal,
      )
      return NewsEntry[id]
    rescue SQLite3::BusyException
      sleep(1)
      retry
    rescue Sequel::UniqueConstraintViolation
      return nil
    rescue => e
      logger.error(source: feed&.id, error: e, entry:)
      return nil
    end

    def self.create_title(title, feed)
      pattern = / [|-] .+$/
      dest = title.sanitize
      dest.gsub!(pattern, '') while dest.match?(pattern)
      return dest
    rescue => e
      logger.error(source: feed&.id, error: e)
      return title
    end
  end
end
