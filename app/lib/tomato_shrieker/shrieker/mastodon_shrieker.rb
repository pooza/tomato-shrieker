module TomatoShrieker
  class MastodonShrieker < Ginseng::Fediverse::MastodonService
    include Package

    def exec(body)
      body = body.clone
      body[:media_ids] ||= []
      if body[:attachments]
        (body[:attachments] || []).each do |attachment|
          body[:media_ids].push(upload_remote_resource(attachment[:image_url], {response: :id}))
        end
        body.delete(:attachments)
      end
      body[:template][:tag] = true
      body[:status] = body[:template].to_s.strip
      body.delete(:template)
      body[:visibility] = Ginseng::Fediverse::TootParser.visibility_name(body[:visibility])
      return toot(body)
    end
  end
end
