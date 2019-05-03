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
