module TomatoShrieker
  extend Rake::DSL

  namespace :tomato do
    namespace :feed do
      FeedSource.all do |source|
        namespace source.id do
          desc "fetch entries of #{source.id} (#{source.uri})"
          task :fetch do
            puts JSON.pretty_generate(source.summary)
          end
        end
      end
    end
  end
end
