require 'yaml'
require 'mastodon'
require 'tomato-toot/feed'

module TomatoToot
  class Application
    def execute (options)
      config['local']['feeds'].each do |feed|
        feed = TomatoToot::Feed.new(feed, config)
        feed.bodies(options).each do |item|
          mastodon.create_status(item)
        end
        feed.touch
      end
    rescue => e
      puts "#{e.class} #{e.message}"
      exit 1
    end

    private
    def config
      unless @config
        @config = {}
        Dir.glob(File.join(ROOT_DIR, 'config', '*.yaml')).each do |f|
          @config[File.basename(f, '.yaml')] = YAML.load_file(f)
        end
      end
      return @config
    end

    def mastodon
      return ::Mastodon::REST::Client.new({
        base_url: config['local']['services']['mastodon']['url'],
        bearer_token: config['local']['services']['mastodon']['access_token'],
      })
    end
  end
end
