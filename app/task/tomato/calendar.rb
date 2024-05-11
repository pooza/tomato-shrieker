module TomatoShrieker
  extend Rake::DSL

  namespace :tomato do
    namespace :source do
      IcalendarSource.all do |source|
        namespace source.id do
          desc "fetch <#{source.uri}>"
          task :fetch do
            puts source.summary.deep_stringify_keys.to_yaml
          end

          desc "entries <#{source.uri}>"
          task :entries do
            puts source.entries.to_yaml
          end

          desc "shriek <#{source.uri}>"
          task :shriek do
            source.exec
          end
        end
      end
    end
  end
end
