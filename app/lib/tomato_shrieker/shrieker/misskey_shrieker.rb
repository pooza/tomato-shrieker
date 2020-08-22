module TomatoShrieker
  class MisskeyShrieker < Ginseng::Fediverse::MisskeyService
    include Package

    def exec(body)
      body[:fileIds] ||= []
      if body[:attachments]
        (body[:attachments] || []).each do |attachment|
          body[:fileIds].push(upload_remote_resource(attachment[:image_url], {response: :id}))
        end
        body.delete(:attachments)
      end
      body.delete(:fileIds) unless body[:fileIds].present?
      body[:visibility] = Ginseng::Fediverse::NoteParser.visibility_name(body[:visibility])
      return note(body)
    end
  end
end
