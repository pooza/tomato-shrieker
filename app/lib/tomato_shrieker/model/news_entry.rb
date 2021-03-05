module TomatoShrieker
  class NewsEntry < Entry
    def self.create(entry, feed = nil)
      values = entry.clone
      values = values.to_h unless values.is_a?(Hash)
      feed ||= Source.create(values['feed'])
      return if feed.touched? && entry['published'] <= feed.time
      id = insert(
        feed: feed.id,
        title: create_title(values['title']),
        summary: values['summary']&.sanitize,
        url: values['url'],
        published: values['published'].getlocal,
      )
      return NewsEntry[id]
    rescue SQLite3::BusyException
      retry
    rescue => e
      feed.logger.error(error: e, entry: entry)
      return nil
    end

    def self.create_title(title)
      pattern = /( [|-] .+|[（(].+[）)])$/
      dest = title.dup
      dest.gsub!(pattern, '') while dest.match?(pattern)
      return dest
    rescue => e
      feed.logger.error(error: e, entry: entry)
      return title
    end
  end
end
