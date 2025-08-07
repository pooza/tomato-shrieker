$LOAD_PATH.unshift(File.join(File.expand_path(__dir__), 'app/lib'))
ENV['RAKE'] = 'yes'

require 'tomato_shrieker'
Sequel::Model.db = Sequel.connect(TomatoShrieker::Environment.dsn)
TomatoShrieker.load_tasks
