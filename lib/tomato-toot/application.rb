require 'yaml'
require 'mastodon'
require 'tomato-toot/feed'

module TomatoToot
  class Application
    def execute (options)
      config['local']['feeds'].each do |feed|
        feed = TomatoToot::Feed.new(feed, config)
        feed.bodies(options).each do |body|
          mastodon.create_status(body)
          loggerr.info({message: 'tooted', body: body}.to_json)
        end
        feed.touch
      end
      loggerr.info({message: 'executed', options: options}.to_json)
    rescue => e
      puts "#{e.class} #{e.message}"
      loggerr.error({class: e.class, message: e.message}.to_json)
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

    def mastodon
      return ::Mastodon::REST::Client.new({
        base_url: config['local']['services']['mastodon']['url'],
        bearer_token: config['local']['services']['mastodon']['access_token'],
      })
    end
  end
end
