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
      @logger.info({mode: 'webhook', request: {path: request.path, params: params}})
      @renderer = JsonRenderer.new
      @headers = request.env.select{ |k, v| k.start_with?('HTTP_')}
      @json = JSON.parse(request.body.read.to_s) if request.request_method == 'POST'
    end

    after do
      status @renderer.status
      content_type @renderer.type
    end

    get '/about' do
      @renderer.message = Package.full_name
      return @renderer.to_s
    end

    post '/webhook/v1.0/toot/:digest' do
      unless webhook = Webhook.search(params[:digest])
        raise NotFoundError, "Resource #{request.path} not found."
      end
      @json['text'] ||= @json['body']
      raise RequestError, 'empty message' unless @json['text'].present?
      webhook.toot(@json['text'])
      @renderer.message = {text: @json['text']}
      return @renderer.to_s
    end

    get '/webhook/v1.0/toot/:digest' do
      unless Webhook.search(params[:digest])
        raise NotFoundError, "Resource #{request.path} not found."
      end
      @renderer.message = 'OK'
      return @renderer.to_s
    end

    not_found do
      @renderer = JsonRenderer.new
      @renderer.status = 404
      @renderer.message = NotFoundError.new("Resource #{request.path} not found.").to_h
      return @renderer.to_s
    end

    error do |e|
      e = Error.create(e)
      @renderer = JsonRenderer.new
      @renderer.message = e.to_h.delete_if{ |k, v| k == :backtrace}
      Slack.broadcast(e.to_h)
      @logger.error(e.to_h)
      return @renderer.to_s
    end
  end
end
