source 'https://rubygems.org'
ruby '>= 3.4', '< 5.0'
gem 'feedjira', '~>3.0'
gem 'ginseng-core', github: 'pooza/ginseng-core', branch: 'main', require: 'ginseng'
gem 'ginseng-fediverse', github: 'pooza/ginseng-fediverse', branch: 'main',
  require: 'ginseng/fediverse'
gem 'ginseng-piefed', github: 'pooza/ginseng-piefed', branch: 'main', require: 'ginseng/piefed'
gem 'ginseng-youtube', github: 'pooza/ginseng-youtube', branch: 'main', require: 'ginseng/you_tube'
gem 'icalendar'
gem 'icalendar-rrule', github: 'pooza/icalendar-rrule',
  ref: '396a2c3e6b5cf394c2416f39c05e948cccd4ea52'
gem 'json-schema'
# 上流はリレーの TLS 証明書を検証しない（verify_peer: false）ので、検証を戻したフォークを使う (#1740)
gem 'nostr', github: 'pooza/nostr', tag: 'v0.7.1'
gem 'optparse'
gem 'parallel'
gem 'puma'
gem 'rufus-scheduler'
gem 'sentry-ruby'
gem 'sequel'
gem 'sqlite3'
gem 'thor'

group :development do
  gem 'ginseng-style', github: 'pooza/ginseng-style', tag: 'v1.1.14', require: false
  gem 'ricecream'
  gem 'rubocop-sequel'
  gem 'test-unit'
  gem 'webmock'
end
