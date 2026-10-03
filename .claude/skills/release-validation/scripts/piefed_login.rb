# PieFed の認証だけを単独で確かめる。⚠ login は遅延するので明示的に呼ぶ (#1514)。
include TomatoShrieker
Sequel.connect(Environment.dsn)
src = Source.create('test-google-news-piefed')
shr = src.piefed
shr.login
puts "JWT: #{shr.instance_variable_get(:@jwt) ? 'present' : 'absent'}"
