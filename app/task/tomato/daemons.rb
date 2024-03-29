module TomatoShrieker
  extend Rake::DSL

  namespace :tomato do
    [:scheduler].freeze.each do |daemon|
      namespace daemon do
        [:start, :stop].freeze.each do |action|
          desc "#{action} #{daemon}"
          task action do
            ENV['RUBY_YJIT_ENABLE'] = 'yes' if config['/ruby/jit']
            sh "#{File.join(Environment.dir, 'bin', "#{daemon}_daemon.rb")} #{action}"
          rescue => e
            warn "#{e.class} #{daemon}:#{action} #{e.message}"
          end
        end

        desc "restart #{daemon}"
        task restart: ['config:lint', 'migration:run', :stop, :start]
      end
    end
  end

  [:start, :stop, :restart].freeze.each do |action|
    desc "#{action} all"
    multitask action => ["tomato:scheduler:#{action}"]
  end
end
