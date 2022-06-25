module TomatoShrieker
  class GitHubRepositorySource < FeedSource
    def uri
      uri = Ginseng::URI.parse(config['/github/urls/root'])
      uri.path = File.join('/', repos, 'releases.atom')
      return uri
    end

    def repos
      return self['/source/github/repository']
    end

    alias every period

    def negative_keyword
      return super || Regexp.new('Merge pull request')
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.select {|s| s.is_a?(GitHubRepositorySource)}.each(&block)
    end
  end
end
