module TomatoShrieker
  class GitHubRepositorySource < FeedSource
    def uri
      uri = Ginseng::URI.parse(config['/github/urls/root'])
      uri.path = File.join('/', repos, "#{timeline}.atom")
      return uri
    end

    def repository
      return self['/source/github/repository'] || self['/source/github/repos']
    end

    def timeline
      return self['/source/github/timeline'] || 'releases'
    end

    alias repos repository

    alias every period

    def negative_keyword
      return super || Regexp.new('Merge pull request')
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.select {|s| s.is_a?(self)}.each(&block)
    end
  end
end
