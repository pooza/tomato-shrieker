require 'active_support'
require 'active_support/core_ext'
require 'json'
require 'yaml'
require 'mastodon'
require 'syslog/logger'
require 'tomato-toot/feed'

module TomatoToot
  class Application
    def execute
      config['local']['entries'].each do |entry|
        feed = TomatoToot::Feed.new(entry, config)
        if feed.touched?
          mastodon = Mastodon::REST::Client.new({
            base_url: entry['mastodon']['url'],
            bearer_token: entry['mastodon']['token'],
          })
          feed.fetch do |body|
            mastodon.create_status(body)
            logger.info({message: 'toot', body: body}.to_json)
          end
        end
        feed.touch
      end
      logger.info({message: 'complete'}.to_json)
    rescue => e
      puts "#{e.class} #{e.message}"
      logger.error({class: e.class, message: e.message}.to_json)
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

    def logger
      unless @logger
        @logger = Syslog::Logger.new(config['application']['name'])
      end
      return @logger
    end
  end
end
