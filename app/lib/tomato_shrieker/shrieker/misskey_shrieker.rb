module TomatoShrieker
  class MisskeyShrieker < Ginseng::Fediverse::MisskeyService
    include Package

    def exec(body)
      body = body.clone
      body[:fileIds] ||= []
      if (attachments = body.delete(:attachments))
        threads = Environment.parallel_thread_count
        body[:fileIds] = Parallel.map(attachments, in_threads: threads) do |v|
          upload_remote_resource(v[:image_url], {response: :id})
        end
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
