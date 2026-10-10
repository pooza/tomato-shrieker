# PieFed の認証だけを単独で確かめる。⚠ login は遅延するので明示的に呼ぶ (#1514)。
Sequel.connect(TomatoShrieker::Environment.dsn)
src = TomatoShrieker::Source.create('test-google-news-piefed')
shr = src.piefed
shr.login
puts "JWT: #{shr.instance_variable_get(:@jwt) ? 'present' : 'absent'}"
