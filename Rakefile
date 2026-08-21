$LOAD_PATH.unshift(File.join(File.expand_path(__dir__), 'app/lib'))
ENV['RAKE'] = 'yes'

require 'tomato_shrieker'
module TomatoShrieker
  Sequel.connect(Environment.dsn)
  load_tasks
  # ⚠ **`environment:` を渡すこと (#1517)。**既定は `Ginseng::Environment` ＝ gem の
  # ルートを指すので、`cert:update` が gem 側に cert/cacert.pem を作ってしまう。
  Ginseng.load_tasks(environment: Environment)
end
