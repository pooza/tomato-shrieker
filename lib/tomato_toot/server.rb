module TomatoToot
  class Server < Ginseng::Sinatra
    include Package

    post '/webhook/v1.0/toot/:digest' do
      unless Webhook.create(params[:digest])
        raise Ginseng::NotFoundError, "Resource #{request.path} not found."
      end
      params[:text] ||= params[:body]
      raise Ginseng::RequestError, 'empty message' unless params[:text].present?
      webhook = Webhook.create(params[:digest])
      webhook.toot(params[:text])
      @renderer.message = {text: params[:text]}
      return @renderer.to_s
    end

    get '/webhook/v1.0/toot/:digest' do
      unless Webhook.create(params[:digest])
        raise Ginseng::NotFoundError, "Resource #{request.path} not found."
      end
      @renderer.message = 'OK'
      return @renderer.to_s
    end

    error do |e|
      e = Ginseng::Error.create(e)
      @renderer = default_renderer_class.constantize.new
      @renderer.status = e.status
      @renderer.message = e.to_h.delete_if{ |k, v| k == :backtrace}
      Slack.broadcast(e.to_h)
      @logger.error(e.to_h)
      return @renderer.to_s
    end
  end
end
