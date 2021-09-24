module TomatoShrieker
  extend Rake::DSL

  namespace :tomato do
    desc 'clear entries'
    task :clean do
      Entry.dataset.destroy
    end
  end
end
