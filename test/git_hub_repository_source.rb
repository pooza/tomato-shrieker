module TomatoShrieker
  class GitHubRepositorySourceTest < TestCase
    def test_all
      assert_kind_of(Enumerator, GitHubRepositorySource.all)
    end

    def test_repository
      GitHubRepositorySource.all do |source|
        assert_kind_of(String, source.repository)
        assert_predicate(source.repository, :present?)
        assert_kind_of(String, source.repos)
        assert_predicate(source.repos, :present?)
      end
    end
  end
end
