module TomatoToot
  class MastodonShrieker < Ginseng::Fediverse::MastodonService
    include Package

    def exec(params)
      params[:media_ids] ||= []
      if params[:image_url]
        params[:media_ids].push(upload_remote_resource(params[:image_url]))
        params.delete(:image_url)
      end
      return toot(params)
    end
  end
end
