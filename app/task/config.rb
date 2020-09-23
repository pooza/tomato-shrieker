namespace :config do
  desc 'lint local config'
  task :lint do
    puts 'schema:'
    puts TomatoShrieker::Config.instance.schema.to_yaml
    if TomatoShrieker::Config.instance.errors.present?
      puts 'result:'
      puts TomatoShrieker::Config.instance.errors.to_yaml
      exit 1
    else
      puts 'result: OK'
    end
  end
end
