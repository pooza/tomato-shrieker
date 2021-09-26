module TomatoShrieker
  extend Rake::DSL

  namespace :migration do
    desc 'migrate database'
    task run: [:db] do
      path = File.join(Environment.dir, 'app/migration')
      sh "bundle exec sequel -m #{path} '#{Environment.dsn}' -E"
    end

    file :db do
      FileUtils.touch(Environment.db)
    end
  end
end
