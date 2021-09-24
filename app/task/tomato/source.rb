module TomatoShrieker
  extend Rake::DSL

  namespace :tomato do
    namespace :source do
      desc 'source list'
      task :list do
        Source.all do |source|
          puts JSON.pretty_generate(source.to_h)
        end
      end
    end
  end
end
