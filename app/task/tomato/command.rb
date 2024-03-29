module TomatoShrieker
  extend Rake::DSL

  namespace :tomato do
    namespace :source do
      CommandSource.all do |source|
        namespace source.id do
          if source.bundler?
            desc 'bundle install'
            task :bundler do
              source.command.bundle_install
            end
          end

          desc "execute '#{source.command}'"
          task :exec do
            start = Time.now
            source.command.exec
            puts source.command.stdout
            warn ''
            warn "(elapsed: #{(Time.now - start).round(2)}s)"
          end

          desc "shriek '#{source.command}'"
          task :shriek do
            source.exec
          end
        end
      end
    end
  end
end
