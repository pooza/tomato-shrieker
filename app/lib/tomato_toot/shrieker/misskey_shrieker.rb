module TomatoToot
  class MisskeyShrieker < Ginseng::Fediverse::MisskeyService
    include Package

    def exec(params)
      params[:fileIds] ||= []
      if params[:image_url]
        params[:fileIds].push(upload_remote_resource(params[:image_url]))
        params.delete(:image_url)
      end
      return note(params)
    end
  end
end
