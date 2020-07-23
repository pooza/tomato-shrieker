module TomatoToot
  class WebhookShrieker < Ginseng::Slack
    include Package

    def exec(params)
      params[:attachments] ||= []
      if params[:image_url]
        params[:attachments].push(image_url: params[:image_url])
        params.delete(:image_url)
      end
      params[:text] = params[:status]
      params.delete(:status)
      return say(params, :hash)
    end
  end
end
