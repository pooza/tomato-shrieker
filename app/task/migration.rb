require 'fileutils'

namespace :migration do
  def path
    return File.join(
      TomatoToot::Environment.dir,
      'app/migration',
    )
  end

  desc 'migrate database'
  task run: [:db] do
    sh "bundle exec sequel -m #{path} '#{TomatoToot::Environment.dsn}' -E"
  end

  file :db do
    FileUtils.touch(TomatoToot::Environment.db)
  end
end

desc 'alias of migration:run'
task migrate: 'migration:run'
