module TomatoShrieker
  class MisskeyShrieker < Ginseng::Fediverse::MisskeyService
    include Package
    include RemoteAttachment

    def exec(body)
      body = body.clone
      body[:fileIds] ||= []
      if (attachments = body.delete(:attachments))
        body[:fileIds] = upload_attachments(attachments, source: body[:template]&.source)
      end
      body[:template][:tag] = true
      body[:text] = body[:template].to_s.strip
      body[:visibility] = Ginseng::Fediverse::NoteParser.visibility_name(body[:visibility])
      if spoiler_text = body[:template].source.spoiler_text
        body[:cw] = spoiler_text
      end
      body.delete(:template)
      return note(body)
    end
  end
end
