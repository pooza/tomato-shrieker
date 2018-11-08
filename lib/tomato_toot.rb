require 'active_support'
require 'active_support/core_ext'
require 'active_support/dependencies/autoload'

module TomatoToot
  extend ActiveSupport::Autoload

  autoload :Bitly
  autoload :Config
  autoload :FeedEntry
  autoload :Feed
  autoload :Logger
  autoload :Mastodon
  autoload :Package
  autoload :Renderer
  autoload :Server
  autoload :Slack
  autoload :Standalone
  autoload :Webhook

  autoload_under 'error' do
    autoload :ConfigError
    autoload :ExternalServiceError
    autoload :ImprementError
    autoload :NotFoundError
    autoload :RequestError
  end

  autoload_under 'renderer' do
    autoload :JsonRenderer
  end
end
