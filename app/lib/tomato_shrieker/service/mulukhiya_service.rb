require 'sanitize'

module TomatoShrieker
  class MulukhiyaService < Ginseng::Fediverse::MulukhiyaService
    include Package

    def search_hashtags(text)
      params = {
        body: {q: Sanitize.clean(text)}.to_json,
      }
      tags = []
      @http.post('/mulukhiya/api/tagging/tag/search', params).each_value do |entry|
        tags.concat(entry['words'])
      end
      return tags.uniq.compact
    end
  end
end
