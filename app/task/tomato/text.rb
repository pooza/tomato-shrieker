module TomatoShrieker
  extend Rake::DSL

  namespace :tomato do
    namespace :source do
      TextSource.all do |source|
        namespace source.id do
          desc "shriek #{source.text.ellipsize(40).to_json}"
          task :shriek do
            source.exec
          end
        end
      end
    end
  end
end
