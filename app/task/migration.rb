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
    sh "bundle exec sequel -m #{path} '#{TomatoToot.dsn}' -E"
  end

  file :db do
    FileUtils.touch(TomatoToot.db_path)
  end
end
