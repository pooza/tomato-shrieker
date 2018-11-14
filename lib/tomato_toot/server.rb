require 'sinatra'

module TomatoToot
  class Server < Sinatra::Base
    def initialize
      super
      @config = Config.instance
      @logger = Logger.new
      @logger.info({
        mode: 'webhook',
        message: 'starting...',
        server: {port: @config['thin']['port']},
        version: Package.version,
      })
    end

    before do
      @message = {
        mode: 'webhook',
        request: {path: request.path, params: params},
        response: {},
      }
      @renderer = JsonRenderer.new
      @headers = request.env.select{ |k, v| k.start_with?('HTTP_')}
      if request.request_method == 'POST'
        @json = JSON.parse(request.body.read.to_s)
        @message[:request][:params] = @json
      end
    end

    after do
      @message[:response][:status] ||= @renderer.status
      if @renderer.status < 400
        @logger.info(@message.select{ |k, v| [:request, :response].member?(k)})
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

    post '/webhook/v1.0/toot/:digest' do
      unless webhook = Webhook.search(params[:digest])
        raise NotFoundError, "Resource #{@message[:request][:path]} not found."
      end
      @json['text'] ||= @json['body']
      raise RequestError, 'empty message' unless @json['text']
      webhook.toot(@json['text'])
      @message[:response][:text] = @json['text']
      @renderer.message = @message
      return @renderer.to_s
    end

    get '/webhook/v1.0/toot/:digest' do
      unless Webhook.search(params[:digest])
        raise NotFoundError, "Resource #{@message[:request][:path]} not found."
      end
      @message[:response][:text] = 'OK'
      @renderer.message = @message
      return @renderer.to_s
    end

    not_found do
      @renderer = JsonRenderer.new
      @renderer.status = 404
      @message[:response][:message] = "Resource #{@message[:request][:path]} not found."
      @renderer.message = @message
      return @renderer.to_s
    end

    error do |e|
      @renderer = JsonRenderer.new
      begin
        @renderer.status = e.status
      rescue NoMethodError
        @renderer.status = 500
      end
      @message[:response][:error] = "#{e.class}: #{e.message}"
      @message[:backtrace] = e.backtrace[0..5]
      @renderer.message = @message
      Slack.broadcast(@message)
      return @renderer.to_s
    end
  end
end
