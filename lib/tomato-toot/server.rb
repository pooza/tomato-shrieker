require 'sinatra'
require 'active_support'
require 'active_support/core_ext'
require 'tomato-toot/config'
require 'tomato-toot/webhook'
require 'tomato-toot/package'
require 'tomato-toot/logger'
require 'tomato-toot/json'
require 'tomato-toot/slack'

module TomatoToot
  class Server < Sinatra::Base
    def initialize
      super
      @config = Config.instance
      @slack = Slack.new if @config['local']['slack']
      @logger = Logger.new
      @logger.info({
        mode: 'server',
        message: 'starting...',
        server: {port: @config['thin']['port']},
      })
    end

    before do
      @message = {
        mode: 'server',
        request: {path: request.path, params: params},
        response: {},
      }
      @renderer = JSON.new
    end

    after do
      @message[:response][:status] ||= @renderer.status
      if @renderer.status < 400
        @logger.info(@message)
      else
        @logger.error(@message)
      end
      status @renderer.status
      content_type @renderer.type
    end

    get '/about' do
      @message[:response][:message] = Package.full_name
      @renderer.message = @message
      return @renderer.to_s
    end

    post '/webhook/:digest' do
      unless webhook = Webhook.search(params[:digest])
        @renderer.status = 404
        return @renderer.to_s
      end

      json = ::JSON.parse(request.body.read.to_s)
      unless json['text']
        @renderer.status = 400
        @message[:response][:message] = 'empty message'
        @renderer.message = @message
        return @renderer.to_s
      end

      webhook.toot(json['text'])
      @message[:request][:params] = json
      @message[:response][:text] = json['text']
      @renderer.message = @message
      return @renderer.to_s
    end

    not_found do
      @renderer = JSON.new
      @renderer.status = 404
      @message[:response][:message] = "Resource #{@message[:request][:path]} not found."
      @renderer.message = @message
      return @renderer.to_s
    end

    error do
      @renderer = JSON.new
      @renderer.status = 500
      @message[:response][:message] = env['sinatra.error'].message
      @renderer.message = @message
      @slack.say(@message) if @slack
      return @renderer.to_s
    end
  end
end
