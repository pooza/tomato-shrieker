$LOAD_PATH.unshift(File.join(File.expand_path(__dir__), 'app/lib'))
ENV['RAKE'] = 'yes'

require 'tomato_shrieker'
module TomatoShrieker
  Sequel::Model.db = Sequel.connect(Environment.dsn)
  load_tasks
end
