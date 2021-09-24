module TomatoShrieker
  extend Rake::DSL

  namespace :tomato do
    namespace :source do
      desc 'source list'
      task :list do
        Source.all do |source|
          puts source.to_h.deep_stringify_keys.to_yaml
        end
      end
    end
  end
end
