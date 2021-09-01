module TomatoShrieker
  extend Rake::DSL
  include Package

  namespace :config do
    desc 'lint local config'
    task :lint do
      puts 'schema:'
      puts config.schema.to_yaml
      if config.errors.present?
        puts 'result:'
        puts config.errors.to_yaml
        exit 1
      else
        puts 'result: OK'
      end
    end
  end
end
