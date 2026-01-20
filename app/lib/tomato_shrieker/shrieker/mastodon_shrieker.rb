module TomatoShrieker
  class MastodonShrieker < Ginseng::Fediverse::MastodonService
    include Package

    def exec(body)
      body = body.clone
      body[:media_ids] ||= []
      if (attachments = body.delete(:attachments))
        threads = Environment.parallel_thread_count
        body[:media_ids] = Parallel.map(attachments, in_threads: threads) do |v|
          upload_remote_resource(v[:image_url], {response: :id})
        end
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
