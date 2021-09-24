module TomatoShrieker
  extend Rake::DSL

  namespace :tomato do
    namespace :command do
      CommandSource.all do |source|
        namespace source.id do
          desc "bundle install #{source.id}"
          task :bundler do
            source.command.bundle_install
          end

          desc "execute #{source.id}"
          task :exec do
            start = Time.now
            source.command.exec
            puts source.command.stdout
            warn ''
            warn "(elapsed: #{(Time.now - start).round(2)}s)"
          end
        end
      end
    end
  end
end
