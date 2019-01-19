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
  autoload :Logger
  autoload :Mastodon
  autoload :Package
  autoload :Server
  autoload :Slack
  autoload :Standalone
  autoload :Webhook
end
