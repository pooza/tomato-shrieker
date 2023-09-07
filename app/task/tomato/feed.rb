module TomatoShrieker
  extend Rake::DSL

  namespace :tomato do
    namespace :source do
      FeedSource.all do |source|
        namespace source.id do
          desc "fetch <#{source.uri}>"
          task :fetch do
            puts source.summary.deep_stringify_keys.to_yaml
          end

          desc "shriek <#{source.uri}>"
          task :shriek do
            source.exec
          end

          desc 'touch'
          task :touch do
            source.touch
          end

          desc 'delete all records'
          task :clear do
            source.clear
          end

          if source.purgeable?
            desc "delete records (< #{source.keep_years.years.ago.strftime('%Y/%m/%d')})"
            task :purge do
              source.purge
            end
          end
        end
      end
    end
  end
end
