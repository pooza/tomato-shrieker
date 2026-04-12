module TomatoShrieker
  extend Rake::DSL

  namespace :tomato do
    [:scheduler].freeze.each do |daemon|
      daemon_path = File.join(Environment.dir, 'bin', "#{daemon}_daemon.rb")

      namespace daemon do
        desc "stop #{daemon}"
        task :stop do
          sh "#{daemon_path} stop"
        rescue => e
          warn "#{e.class} #{daemon}:stop #{e.message}"
        end

        desc "start #{daemon}"
        task start: ['config:lint', 'migration:run'] do
          sh "#{daemon_path} restart"
        rescue => e
          warn "#{e.class} #{daemon}:start #{e.message}"
        end

        desc "restart #{daemon}"
        task restart: ['config:lint', 'migration:run'] do
          sh "#{daemon_path} restart"
        rescue => e
          warn "#{e.class} #{daemon}:restart #{e.message}"
        end
      end
    end
  end

  [:start, :stop, :restart].freeze.each do |action|
    desc "#{action} all"
    multitask action => ["tomato:scheduler:#{action}"]
  end
end
