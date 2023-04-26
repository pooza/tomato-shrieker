module TomatoShrieker
  class MisskeyShrieker < Ginseng::Fediverse::MisskeyService
    include Package

    def exec(body)
      body = body.clone
      body[:fileIds] ||= []
      if body[:attachments]
        (body[:attachments] || []).each do |attachment|
          body[:fileIds].push(upload_remote_resource(attachment[:image_url], {response: :id}))
        end
        body.delete(:attachments)
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
