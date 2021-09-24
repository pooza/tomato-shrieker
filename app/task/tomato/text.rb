module TomatoShrieker
  extend Rake::DSL

  namespace :tomato do
    namespace :text do
      TextSource.all do |source|
        namespace source.id do
          desc "shriek '#{source.text}'"
          task :shriek do
            source.exec
          end
        end
      end
    end
  end
end
