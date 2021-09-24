module TomatoShrieker
  extend Rake::DSL

  namespace :tomato do
    namespace :source do
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

          desc 'clear all records'
          task :clear do
            source.clear
          end

          if source.purge?
            desc "clear records (< #{source.keep_years.years.ago.strftime('%Y/%m/%d')})"
            task :purge do
              source.purge
            end
          end
        end
      end
    end
  end
end
