module TomatoToot
  class MastodonShrieker < Ginseng::Fediverse::MastodonService
    include Package

    def exec(body)
      body[:media_ids] ||= []
      if body[:attachments]
        (body[:attachments] || []).each do |attachment|
          body[:media_ids].push(upload_remote_resource(attachment[:image_url], {response: :id}))
        end
        body.delete(:attachments)
      end
      if body[:text]
        body[:status] = body[:text]
        body.delete(:text)
      end
      return toot(body)
    end
  end
end
