module TomatoShrieker
  class MastodonShrieker < Ginseng::Fediverse::MastodonService
    include Package
    include RemoteAttachment

    def exec(body)
      body = body.clone
      body[:media_ids] ||= []
      if (attachments = body.delete(:attachments))
        body[:media_ids] = upload_attachments(attachments, source: body[:template].source)
      end
      body[:template][:tag] = true
      body[:status] = body[:template].to_s.strip
      body[:visibility] = Ginseng::Fediverse::TootParser.visibility_name(body[:visibility])
      if spoiler_text = body[:template].source.spoiler_text
        body[:spoiler_text] = spoiler_text
      end
      body.delete(:template)
      return toot(body)
    end
  end
end
