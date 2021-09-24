module TomatoShrieker
  extend Rake::DSL

  namespace :tomato do
    namespace :feed do
      FeedSource.all do |source|
        namespace source.id do
          desc "fetch <#{source.uri}>"
          task :fetch do
            puts JSON.pretty_generate(source.summary)
          end

          desc "shriek <#{source.uri}>"
          task :shriek do
            source.exec
          end

          desc 'clear records'
          task :clear do
            source.clear
          end

          if source.keep_years
            desc "purge (#{source.keep_years} years)"
            task :purge do
              source.purge
            end
          end
        end
      end
    end
  end
end
