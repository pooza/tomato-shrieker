require 'bootsnap'

Bootsnap.setup(
  cache_dir: File.join(File.expand_path('..', __dir__), 'tmp/cache'),
  load_path_cache: true,
  autoload_paths_cache: true,
  compile_cache_iseq: true,
  compile_cache_yaml: true,
)

require 'active_support'
require 'active_support/core_ext'
require 'active_support/dependencies/autoload'
require 'ginseng'

module TomatoToot
  extend ActiveSupport::Autoload

  autoload :Bitly
  autoload :Config
  autoload :Environment
  autoload :FeedEntry
  autoload :Feed
  autoload :HTTP
  autoload :Logger
  autoload :Mastodon
  autoload :Package
  autoload :Slack
  autoload :Webhook
  autoload :Template
end
