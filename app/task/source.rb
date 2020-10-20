namespace :tomato do
  namespace :source do
    desc 'source list'
    task :list do
      TomatoShrieker::Source.all do |source|
        puts YAML.dump(source.to_h)
      end
    end
  end
end
