namespace :migration do
  def path
    return File.join(
      TomatoShrieker::Environment.dir,
      'app/migration',
    )
  end

  desc 'migrate database'
  task run: [:db] do
    sh "bundle exec sequel -m #{path} '#{TomatoShrieker::Environment.dsn}' -E"
  end

  file :db do
    FileUtils.touch(TomatoShrieker::Environment.db)
  end
end

desc 'alias of migration:run'
task migrate: 'migration:run'
