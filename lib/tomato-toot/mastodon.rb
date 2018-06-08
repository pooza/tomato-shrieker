require 'mastodon'
require 'tomato-toot/config'

module TomatoToot
  class Mastodon < Mastodon::REST::Client
  end
end
