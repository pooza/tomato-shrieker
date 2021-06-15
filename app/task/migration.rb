namespace :migration do
  desc 'migrate database'
  task run: [:db] do
    path = File.join(TomatoShrieker::Environment.dir, 'app/migration')
    sh "bundle exec sequel -m #{path} '#{TomatoShrieker::Environment.dsn}' -E"
  end

  file :db do
    FileUtils.touch(TomatoShrieker::Environment.db)
  end
end

desc 'alias of migration:run'
task migrate: 'migration:run'
